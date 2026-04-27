defmodule AutolaunchWeb.RateLimiter do
  @moduledoc false

  use GenServer

  @name __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, @name))
  end

  def check(key, limit, window_ms)
      when is_integer(limit) and limit > 0 and is_integer(window_ms) and window_ms > 0 do
    case Process.whereis(@name) do
      nil -> :ok
      _pid -> GenServer.call(@name, {:check, key, limit, window_ms})
    end
  end

  def reset do
    case Process.whereis(@name) do
      nil -> :ok
      _pid -> GenServer.call(@name, :reset)
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:check, key, limit, window_ms}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case Map.get(state, key) do
      {count, window_started_at} when now - window_started_at < window_ms and count >= limit ->
        retry_after_ms = window_ms - (now - window_started_at)
        {:reply, {:error, retry_after_ms}, state}

      {count, window_started_at} when now - window_started_at < window_ms ->
        {:reply, :ok, Map.put(state, key, {count + 1, window_started_at})}

      _expired_or_missing ->
        {:reply, :ok, Map.put(state, key, {1, now})}
    end
  end

  def handle_call(:reset, _from, _state), do: {:reply, :ok, %{}}
end
