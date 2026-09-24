defmodule FormFlow.Data.Instances.Flows.Snapshot do
  @moduledoc """
  What a journey's flow looked like at the moment the journey completed -
  the map `FormFlow.Data.Instances.Flows.complete/2` writes to
  `completed_template_snapshot` on the journey's row.

  A flow is mutable and unversioned: edits reach every journey in flight,
  and a completed journey's `status` may legitimately disagree with what
  `FormFlow.Data.Instances.FlowProgress` derives from the tree later
  (`FormFlow.Data.Instances.Flow`). This snapshot is the one recorded
  answer to "what did this flow look like when I finished it?" - taken
  once, at the one moment the journey stops moving, and never recomputed.

  Two parts, both plain maps with string keys so they store as JSON on
  either adapter:

    * `"tree"` - `FormFlow.Data.Templates.Flows.resolve_tree/1`'s output,
      trimmed to what describes the structure: each flow's identity, its
      nodes (id, slug, labels, properties, form and subflow references),
      its relationships (id, label, properties, source and target), and
      the same for every subflow keyed by the embedding node's id.
    * `"positions"` - `FormFlow.Data.Instances.FlowProgress.forms/2` at
      that moment, one entry per form position in flow order: the path,
      the label, the derived status, and the form instance's id and form
      template version id where one was started.

  Form templates appear by id only. Each form instance already records its
  `template_form_version_id`, and a published version never changes, so
  the definition the user saw is one join away - the rule
  `FormFlow.Web.Components.Forms.Types.Review` follows for the form it
  reviews, applied a level up. Answers are not copied either: they live on
  the form instances, which the journey owns and takes with it when
  deleted, so `FormFlow.Data.Instances.Forms.redact_snapshots/1` has
  nothing to learn about this column.
  """

  alias FormFlow.Data.Instances.FlowProgress
  alias FormFlow.Data.Instances.FormProgress
  alias FormFlow.Data.Templates.Flow

  @doc """
  The snapshot for `tree` (a resolved tree, or `nil` for an unknown flow)
  and the journey's form instances, superseded ones included -
  `FlowProgress` skips those itself.
  """
  @spec take(map() | nil, [struct()]) :: map()
  def take(tree, form_instances) do
    %{
      "tree" => tree_map(tree),
      "positions" => Enum.map(FlowProgress.forms(tree, form_instances), &position_map/1)
    }
  end

  defp tree_map(nil), do: nil

  defp tree_map(%{
         flow: %Flow{} = flow,
         nodes: nodes,
         relationships: relationships,
         subflows: subflows
       }) do
    %{
      "flow" => %{
        "id" => flow.id,
        "name" => flow.name,
        "slug" => flow.slug,
        "label" => flow.label,
        "status" => flow.status
      },
      "nodes" => Enum.map(nodes, &node_map/1),
      "relationships" => Enum.map(relationships, &relationship_map/1),
      "subflows" => Map.new(subflows, fn {node_id, subtree} -> {node_id, tree_map(subtree)} end)
    }
  end

  defp node_map(%Flow.Node{} = node) do
    %{
      "id" => node.id,
      "slug" => node.slug,
      "labels" => node.labels,
      "properties" => node.properties,
      "form_id" => node.form_id,
      "subflow_id" => node.subflow_id
    }
  end

  defp relationship_map(%Flow.Relationship{} = relationship) do
    %{
      "id" => relationship.id,
      "label" => relationship.label,
      "properties" => relationship.properties,
      "source_id" => relationship.source_id,
      "target_id" => relationship.target_id
    }
  end

  defp position_map(%FormProgress{} = form) do
    %{
      "path" => form.path,
      "label" => form.label,
      "status" => Atom.to_string(form.status),
      "instance_id" => form.instance && form.instance.id,
      "version_id" => form.instance && form.instance.template_form_version_id
    }
  end
end
