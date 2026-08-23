defmodule FormFlow.Graph.NodeTest do
  use ExUnit.Case, async: true

  alias FormFlow.Graph.Node

  @graph_id Ecto.UUID.generate()

  test "casts graph_id, labels, and properties" do
    changeset =
      Node.changeset(%Node{}, %{
        graph_id: @graph_id,
        labels: ["Step", "Form"],
        properties: %{"label" => "Contact details"}
      })

    assert changeset.valid?
    assert changeset.changes.graph_id == @graph_id
    assert changeset.changes.labels == ["Step", "Form"]
    assert changeset.changes.properties == %{"label" => "Contact details"}
  end

  test "requires graph_id" do
    changeset = Node.changeset(%Node{}, %{labels: ["Step"]})

    refute changeset.valid?
    assert %{graph_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "labels and properties default rather than being required" do
    changeset = Node.changeset(%Node{}, %{graph_id: @graph_id})

    assert changeset.valid?

    node = Ecto.Changeset.apply_changes(changeset)

    assert node.labels == []
    assert node.properties == %{}
  end

  test "rejects labels that are not a list of strings" do
    changeset = Node.changeset(%Node{}, %{graph_id: @graph_id, labels: "Step"})

    refute changeset.valid?
    assert %{labels: ["is invalid"]} = errors_on(changeset)
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
