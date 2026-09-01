defmodule FormFlow.Web.Instances.Paths do
  @moduledoc """
  `FormFlow.Web.Instances.Paths` module contains the URLs of the user-facing
  pages, built in one place so the shape can change in one place.

  They mirror the template pages (`FormFlow.Web.Templates`) deliberately: same
  nouns, because the mount root already says which world you are in —
  `/admin/flows/:id` is a flow *template*, `/users/flows/:id` is a flow
  *instance*, and each is what `FormFlow.Data.Templates.Flow` and
  `FormFlow.Data.Instances.Flow` respectively call itself.

  A form is addressed by its **position**, not by its instance row:
  `/flows/:id/forms/:node_id`, with one extra segment per subflow drilled
  through — the `path` a `FormFlow.Data.Instances.Form` stamps at creation.
  Addressing the position means the URL exists before the row does, which is
  what lets every navigation to a form be an ordinary link.
  """

  @doc "The user's flow instances."
  def flows_path(base), do: "#{base}/flows"

  @doc "One flow instance: its forms and their progress."
  def flow_path(base, flow_instance_id), do: "#{flows_path(base)}/#{flow_instance_id}"

  @doc "The answers at a position, read-only."
  def form_path(base, flow_instance_id, path) do
    "#{flow_path(base, flow_instance_id)}/forms/#{Enum.join(path, "/")}"
  end

  @doc "The editable form at a position — the page that starts it."
  def form_edit_path(base, flow_instance_id, path) do
    "#{form_path(base, flow_instance_id, path)}/edit"
  end
end
