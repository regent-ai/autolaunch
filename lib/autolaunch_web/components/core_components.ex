defmodule AutolaunchWeb.CoreComponents do
  @moduledoc false
  use Phoenix.Component

  use Gettext, backend: AutolaunchWeb.Gettext

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="al-flash-stack">
      <%= for {kind, message} <- @flash, kind in [:info, :error] do %>
        <div class={["al-flash", kind == :error && "is-error"]}>
          <span class="font-display">{String.upcase(to_string(kind))}</span>
          <p>{message}</p>
        </div>
      <% end %>
    </div>
    """
  end
end
