defmodule Autolaunch.Revenue.IngressAccounts do
  @moduledoc false

  alias Autolaunch.Revenue.Core

  defdelegate get_ingress(subject_id, current_human \\ nil), to: Core
  defdelegate ingress_state(subject_id, current_human \\ nil), to: Core
  defdelegate accounting_tags(subject_id, attrs, current_human \\ nil), to: Core
end
