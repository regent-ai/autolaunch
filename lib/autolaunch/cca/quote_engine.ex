defmodule Autolaunch.CCA.QuoteEngine do
  @moduledoc false

  alias Autolaunch.CCA.Contract

  @mps_total 10_000_000
  @q96 79_228_162_514_264_337_593_543_950_336

  def quote(chain_id, auction_address, amount_wei, max_price_q96) do
    with {:ok, snapshot} <- Contract.snapshot(chain_id, auction_address),
         {:ok, tick_book} <-
           Contract.load_ticks(chain_id, auction_address, snapshot.floor_price_q96),
         {:ok, quote} <- build_quote(snapshot, tick_book, amount_wei, max_price_q96) do
      {:ok, Map.put(quote, :snapshot, snapshot)}
    end
  end

  def build_quote(snapshot, tick_book, amount_wei, max_price_q96)
      when is_integer(amount_wei) and amount_wei > 0 and is_integer(max_price_q96) and
             max_price_q96 > 0 do
    checkpoint = snapshot.checkpoint

    with :ok <- ensure_bid_price(snapshot, checkpoint, max_price_q96),
         # v1 assumes the remaining auction schedule is a single standard release path,
         # so the remaining MPS from the current checkpoint to end-of-auction is sufficient.
         {:ok, remaining_mps} <- remaining_mps(checkpoint.cumulative_mps) do
      amount_q96 = amount_wei * @q96
      effective_amount_q96 = div(amount_q96 * @mps_total, remaining_mps)

      synthetic_ticks = merge_synthetic_bid(tick_book, max_price_q96, effective_amount_q96)

      projected =
        project_market(
          snapshot,
          checkpoint.clearing_price_q96,
          synthetic_ticks,
          effective_amount_q96
        )

      {status_band, would_be_active_now, currency_spent_q96, tokens_filled_units} =
        projected_fill(snapshot, projected, amount_q96, max_price_q96, remaining_mps)

      {:ok,
       %{
         amount_wei: amount_wei,
         amount_q96: amount_q96,
         max_price_q96: max_price_q96,
         current_clearing_price_q96: checkpoint.clearing_price_q96,
         projected_clearing_price_q96: projected.clearing_price_q96,
         quote_mode: "onchain_exact_v1",
         status_band: status_band,
         would_be_active_now: would_be_active_now,
         estimated_tokens_if_end_now_units: 0,
         estimated_tokens_if_no_other_bids_change_units: tokens_filled_units,
         currency_spent_q96: currency_spent_q96,
         inactive_above_price_q96: max_price_q96,
         warnings:
           warnings(
             status_band,
             checkpoint.cumulative_mps,
             snapshot.end_block,
             snapshot.block_number
           )
       }}
    end
  end

  def build_quote(_snapshot, _tick_book, _amount_wei, _max_price_q96),
    do: {:error, :invalid_quote_input}

  defp ensure_bid_price(snapshot, checkpoint, max_price_q96) do
    cond do
      max_price_q96 > snapshot.max_bid_price_q96 ->
        {:error, :max_price_too_high}

      rem(max_price_q96 - snapshot.floor_price_q96, snapshot.tick_spacing_q96) != 0 ->
        {:error, :invalid_tick_price}

      max_price_q96 <= checkpoint.clearing_price_q96 ->
        {:error, :bid_must_be_above_clearing_price}

      snapshot.block_number >= snapshot.end_block ->
        {:error, :auction_is_over}

      snapshot.block_number < snapshot.start_block ->
        {:error, :auction_not_started}

      true ->
        :ok
    end
  end

  defp remaining_mps(cumulative_mps) when cumulative_mps < @mps_total,
    do: {:ok, @mps_total - cumulative_mps}

  defp remaining_mps(_cumulative_mps), do: {:error, :auction_sold_out}

  defp merge_synthetic_bid(tick_book, max_price_q96, effective_amount_q96) do
    existing =
      Map.get(tick_book, max_price_q96, %{
        price_q96: max_price_q96,
        next_price_q96: 0,
        currency_demand_q96: 0
      })

    Map.put(tick_book, max_price_q96, %{
      existing
      | currency_demand_q96: existing.currency_demand_q96 + effective_amount_q96
    })
  end

  defp project_market(snapshot, current_clearing_price_q96, tick_book, effective_amount_q96) do
    active_ticks =
      tick_book
      |> Map.values()
      |> Enum.filter(fn tick ->
        tick.price_q96 > current_clearing_price_q96 and tick.currency_demand_q96 > 0
      end)
      |> Enum.sort_by(& &1.price_q96)

    sum_demand_above =
      snapshot.sum_currency_demand_above_clearing_q96 + effective_amount_q96

    do_project_market(
      snapshot.total_supply,
      sum_demand_above,
      current_clearing_price_q96,
      current_clearing_price_q96,
      0,
      active_ticks
    )
  end

  defp do_project_market(
         total_supply,
         sum_demand_above,
         minimum_clearing,
         _current_clearing,
         clearing_tick_demand_q96,
         []
       ) do
    clearing = ceil_div(sum_demand_above, total_supply)

    %{
      clearing_price_q96: max(minimum_clearing, clearing),
      sum_currency_demand_above_clearing_q96: sum_demand_above,
      tick_demand_at_clearing_q96:
        if(max(minimum_clearing, clearing) == minimum_clearing,
          do: clearing_tick_demand_q96,
          else: 0
        )
    }
  end

  defp do_project_market(
         total_supply,
         sum_demand_above,
         minimum_clearing,
         current_clearing,
         clearing_tick_demand_q96,
         [tick | rest] = ticks
       ) do
    clearing = ceil_div(sum_demand_above, total_supply)

    if sum_demand_above >= total_supply * tick.price_q96 or clearing == tick.price_q96 do
      do_project_market(
        total_supply,
        sum_demand_above - tick.currency_demand_q96,
        tick.price_q96,
        tick.price_q96,
        tick.currency_demand_q96,
        rest
      )
    else
      final_clearing = max(minimum_clearing, clearing)

      %{
        clearing_price_q96: final_clearing,
        sum_currency_demand_above_clearing_q96: sum_demand_above,
        tick_demand_at_clearing_q96:
          cond do
            final_clearing == tick.price_q96 -> tick.currency_demand_q96
            final_clearing == minimum_clearing -> clearing_tick_demand_q96
            true -> 0
          end,
        next_tick_price_q96: tick.price_q96,
        current_reference_price_q96: current_clearing,
        remaining_ticks: ticks
      }
    end
  end

  defp projected_fill(snapshot, projected, amount_q96, max_price_q96, remaining_mps) do
    cond do
      projected.clearing_price_q96 < max_price_q96 ->
        tokens_filled_units = div(amount_q96, projected.clearing_price_q96)
        {"active", true, amount_q96, tokens_filled_units}

      projected.clearing_price_q96 > max_price_q96 ->
        {"inactive", false, 0, 0}

      true ->
        currency_raised_at_clearing_q96_x7 =
          partial_fill_currency_raised_at_clearing(
            snapshot.total_supply,
            projected,
            remaining_mps
          )

        denominator = projected.tick_demand_at_clearing_q96 * remaining_mps

        currency_spent_q96 =
          full_mul_div_up(amount_q96, currency_raised_at_clearing_q96_x7, denominator)

        tokens_filled_units =
          div(
            full_mul_div(amount_q96, currency_raised_at_clearing_q96_x7, denominator),
            max_price_q96
          )

        {"partial", true, currency_spent_q96, tokens_filled_units}
    end
  end

  defp partial_fill_currency_raised_at_clearing(total_supply, projected, remaining_mps) do
    total_currency_for_delta_q96_x7 = total_supply * projected.clearing_price_q96 * remaining_mps
    currency_above_q96_x7 = projected.sum_currency_demand_above_clearing_q96 * remaining_mps
    calculated = total_currency_for_delta_q96_x7 - currency_above_q96_x7
    maximum = projected.tick_demand_at_clearing_q96 * remaining_mps
    min(calculated, maximum)
  end

  defp warnings(status_band, _cumulative_mps, end_block, block_number) do
    []
    |> maybe_append(status_band == "inactive", "Bid would be outbid on the next checkpoint.")
    |> maybe_append(
      status_band == "partial",
      "Bid would sit exactly on the clearing price and be partially filled."
    )
    |> maybe_append(
      end_block - block_number <= 20,
      "Auction is near the end of its block schedule."
    )
    |> maybe_append(
      true,
      "New bids start participating from the next checkpoint, so \"if ended now\" is exactly zero."
    )
  end

  defp maybe_append(list, true, value), do: list ++ [value]
  defp maybe_append(list, false, _value), do: list

  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)

  defp full_mul_div(a, b, denominator), do: div(a * b, denominator)

  defp full_mul_div_up(a, b, denominator) do
    div(a * b + denominator - 1, denominator)
  end
end
