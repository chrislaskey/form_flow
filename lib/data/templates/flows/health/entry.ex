defmodule FormFlow.Data.Templates.Flows.Health.Entry do
  @moduledoc """
  One entry in a `FormFlow.Data.Templates.Flows.Health` report: something a
  check found about a root flow. An entry, not a problem — a check judges a
  flow from its shape and can be wrong about what is fine on purpose, which
  is why an admin can ignore one (`FormFlow.Data.Templates.Flows.Health.ignore/3`).

  ## Fields

    * `:level` — how much it matters, one of `@levels`, worst first.
      `:error` means a user cannot work the flow as it stands — Start does
      not reach End, a step's form has no published version. `:warning`
      means the flow works but something in it does not take part — a step
      no Start reaches, a step nothing follows. `:info` is something an
      admin may want to act on that changes nothing for users — a draft
      with unpublished changes. The three names are the ones the pages'
      alerts and badges already use for their `kind`.
    * `:code` — a stable atom naming the check that failed, for a caller
      that acts on one kind of entry (`:end_unreachable`,
      `:form_not_published`, …). The full list is in
      `FormFlow.Data.Templates.Flows.Health`'s moduledoc.
    * `:message` — one sentence for an admin, complete on its own: it
      names the step or flow, qualified by the subflows on the way down
      the way the user-facing pages do ("Review / Check pet details").
    * `:subject` — the step or flow the entry is about, as `:message`
      names it: the qualified step label, or, for an entry with a subflow
      itself, the subflows on the way down. `nil` for an entry with the
      root flow itself, which whatever lists the report already names.
    * `:explanation` — a short paragraph on why the check matters: what a
      user meets when the flow is left this way. One per code
      (`explanation/1`), so a host drawing its own page has it.
    * `:fix` — one sentence on what to do about it. One per code (`fix/1`).
    * `:flow_id` — the flow the entry is in: the root, or the owned
      subflow the step sits in.
    * `:node_id` — the node the entry is about, or `nil` for an entry
      with the flow itself (no End, Start does not reach End).
    * `:path` — where in the tree: the node ids from the root flow down,
      the same path `FormFlow.Data.Instances.FormProgress` addresses a
      position by. For a flow-level entry it is the path of the subflow
      node embedding that flow — `[]` for the root. `:code` and `:path`
      together are what identifies an entry from one check to the next.
    * `:ignored` — `nil`, or who set this entry aside and when
      (`FormFlow.Data.Templates.Flows.Health.ignore/3`): `%{user_id:,
      ignored_at:}`. An ignored entry is listed but not counted.
  """

  @levels [:error, :warning, :info]

  @enforce_keys [:level, :code, :message, :flow_id]
  defstruct [
    :level,
    :code,
    :message,
    :subject,
    :explanation,
    :fix,
    :flow_id,
    :node_id,
    :ignored,
    path: []
  ]

  @type level :: :error | :warning | :info

  @type t :: %__MODULE__{
          level: level(),
          code: atom(),
          message: String.t(),
          subject: String.t() | nil,
          explanation: String.t(),
          fix: String.t(),
          flow_id: Ecto.UUID.t(),
          node_id: Ecto.UUID.t() | nil,
          path: [Ecto.UUID.t()],
          ignored: %{user_id: String.t() | nil, ignored_at: DateTime.t() | nil} | nil
        }

  @doc "Every level, worst first."
  @spec levels() :: [level()]
  def levels, do: @levels

  @doc "A level's rank for sorting: `0` for the worst."
  @spec rank(level()) :: non_neg_integer()
  def rank(level), do: Enum.find_index(@levels, &(&1 == level))

  @doc """
  Why an entry with `code` matters: what a user meets when the flow is left
  this way. Written for an admin reading one entry, without the subject —
  `:message` names that.
  """
  @spec explanation(atom()) :: String.t()
  def explanation(:no_start) do
    "Every journey through a flow begins at its Start node. Without one nothing is " <>
      "reachable: no step can be shown, and no instance of the flow can make progress."
  end

  def explanation(:no_end) do
    "A journey completes when it reaches an End node. Without one, users can work every " <>
      "step and never finish: the flow can never be marked complete."
  end

  def explanation(:end_unreachable) do
    "Progress follows the connections forward from Start, and a flow completes only when " <>
      "that walk arrives at End. When it never does, users get stuck at the last connected " <>
      "step with no way to finish."
  end

  def explanation(:form_missing) do
    "A form step is started by opening its form. This step points at no form, or at one " <>
      "that no longer exists, so a user reaching it finds nothing to fill in."
  end

  def explanation(:form_not_published) do
    "Users start a form by pinning its latest published version. Until one exists the step " <>
      "cannot be started, and everything after it waits."
  end

  def explanation(:subflow_missing) do
    "A subflow step opens the flow behind it. This step points at no flow, or at one that " <>
      "could not be loaded, so a user reaching it finds nothing."
  end

  def explanation(:property_missing) do
    "The type marks this property as required: it cannot do its work without a value. A " <>
      "review form with no form to review, for instance, has nothing to show."
  end

  def explanation(:related_form_missing) do
    "The property names a form by its position in the flow, and that position is no longer " <>
      "there — the step was removed, or moved into another subflow. Whatever reads the " <>
      "related form's answers would find none."
  end

  def explanation(:unconnected) do
    "Progress follows the connections forward from Start. A step nothing leads to can never " <>
      "be reached, so users never see it and its form is never filled in."
  end

  def explanation(:dead_end) do
    "A flow completes when End is reached, and End waits only for the steps that lead into " <>
      "it. A step nothing follows can be worked, but the flow completes without it, so its " <>
      "answers may never be looked at."
  end

  def explanation(:no_steps) do
    "Start leads straight to End with nothing between them, so users can start and finish " <>
      "the flow without doing anything. A freshly created flow looks like this until its " <>
      "first step is added."
  end

  def explanation(:unknown_type) do
    "The stored type is not in the host's list — it was renamed or removed after this " <>
      "template chose it. The pages fall back to the default type, so the behaviour the " <>
      "type gave this template is gone."
  end

  def explanation(:stale_perspectives) do
    "The flow is for a perspective its type no longer declares. The stale id is dropped when " <>
      "the page reads it, so the flow may be shown to users it was not meant for, or to " <>
      "nobody."
  end

  def explanation(:unpublished_changes) do
    "The form has a draft that differs from what users see. Nothing is wrong: the published " <>
      "version keeps working. The draft's changes reach users only when it is published."
  end

  @doc "What to do about an entry with `code`, in one sentence."
  @spec fix(atom()) :: String.t()
  def fix(:no_start), do: "Add a Start node to the flow and connect it to the first step."
  def fix(:no_end), do: "Add an End node and connect the last step to it."

  def fix(:end_unreachable),
    do: "Connect the steps so that a path leads from Start to End, one connection at a time."

  def fix(:form_missing) do
    "Delete the step and add it again, which creates a fresh form behind it, or point it at " <>
      "a catalog form with Reuse."
  end

  def fix(:form_not_published), do: "Open the form, review its draft, and publish it."

  def fix(:subflow_missing),
    do: "Delete the step and add it again, which creates a new subflow behind it."

  def fix(:property_missing), do: "Open the flow's or form's settings and set the property."

  def fix(:related_form_missing),
    do: "Point the property at a form the flow still has, or add the form back."

  def fix(:unconnected),
    do: "Connect a step that Start reaches to this one, or delete it if it is not needed."

  def fix(:dead_end), do: "Connect this step onward — to the next step, or to End."
  def fix(:no_steps), do: "Add a step between Start and End."

  def fix(:unknown_type),
    do: "Choose one of the offered types, or restore the missing one in the host's configuration."

  def fix(:stale_perspectives),
    do: "Open the flow's settings and choose its perspectives again from those the type offers."

  def fix(:unpublished_changes),
    do: "Publish the draft when it is ready, or delete it if the changes are not wanted."
end
