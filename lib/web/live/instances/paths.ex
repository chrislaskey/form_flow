defmodule FormFlow.Web.Instances.Paths do
  @moduledoc """
  `FormFlow.Web.Instances.Paths` module contains the URLs of the user-facing
  pages, built in one place so the shape can change in one place.

  The mount root is the index: `base` lists the user's flow instances,
  `base/:id` is one of them, and `base/:id/forms/*path` is a form inside it.
  There is no `/flows` segment and no landing page, unlike the template side
  (`FormFlow.Web.Templates`), because the user-facing side has one section
  and the template side has two — flows and the reusable forms catalog — and
  needs a root that belongs to neither. The mount root already says which
  world you are in: `/admin/flows/:id` is a flow *template*, `/users/:id` is
  a flow *instance*, each what `FormFlow.Data.Templates.Flow` and
  `FormFlow.Data.Instances.Flow` respectively call itself.

  A form is addressed by its **position**, not by its instance row:
  `base/:id/forms/:node_id`, with one extra segment per subflow drilled
  through — the `path` a `FormFlow.Data.Instances.Form` stamps at creation.
  Addressing the position means the URL exists before the row does, which is
  what lets every navigation to a form be an ordinary link.
  """

  @doc "The user's flow instances — the mount root itself."
  def flows_path(""), do: "/"
  def flows_path(base), do: base

  @doc "One flow instance: its forms and their progress."
  def flow_path(base, flow_instance_id), do: "#{base}/#{flow_instance_id}"

  @doc "The answers at a position, read-only."
  def form_path(base, flow_instance_id, path) do
    "#{flow_path(base, flow_instance_id)}/forms/#{Enum.join(path, "/")}"
  end

  @doc "The editable form at a position — the page that starts it."
  def form_edit_path(base, flow_instance_id, path) do
    "#{form_path(base, flow_instance_id, path)}/edit"
  end
end
