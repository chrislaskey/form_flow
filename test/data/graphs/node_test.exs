defmodule FormFlow.Data.Graph.NodeTest do
  use ExUnit.Case, async: true

  alias FormFlow.Data.Graph.Node

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

    assert changeset.changes.properties == %{
             "label" => "Contact details",
             "graph_id" => @graph_id
           }
  end

  test "requires graph_id" do
    changeset = Node.changeset(%Node{}, %{labels: ["Step"]})

    refute changeset.valid?
    assert %{graph_id: ["can't be blank"]} = errors_on(changeset)
  end

  test "casts a caller-supplied id, so replaced contents match existing rows" do
    id = Ecto.UUID.generate()
    changeset = Node.changeset(%Node{}, %{id: id, graph_id: @graph_id})

    assert changeset.valid?
    assert changeset.changes.id == id
  end

  test "labels and properties default rather than being required" do
    changeset = Node.changeset(%Node{}, %{graph_id: @graph_id})

    assert changeset.valid?

    node = Ecto.Changeset.apply_changes(changeset)

    assert node.labels == []
    assert node.properties == %{"graph_id" => @graph_id}
  end

  test "casts subflow_id and copies it into properties" do
    subflow_id = Ecto.UUID.generate()

    changeset =
      Node.changeset(%Node{}, %{graph_id: @graph_id, subflow_id: subflow_id})

    assert changeset.valid?
    assert changeset.changes.subflow_id == subflow_id
    assert changeset.changes.properties["subflow_id"] == subflow_id
  end

  test "adopts subflow_id from properties when the column is not given" do
    # The editor round-trips properties untouched — the reference must survive
    subflow_id = Ecto.UUID.generate()

    changeset =
      Node.changeset(%Node{}, %{
        graph_id: @graph_id,
        properties: %{"subflow_id" => subflow_id, "type" => "subflow"}
      })

    assert changeset.valid?
    assert changeset.changes.subflow_id == subflow_id
  end

  test "an explicit subflow_id wins over the properties copy" do
    explicit = Ecto.UUID.generate()

    changeset =
      Node.changeset(%Node{}, %{
        graph_id: @graph_id,
        subflow_id: explicit,
        properties: %{"subflow_id" => Ecto.UUID.generate()}
      })

    assert changeset.changes.subflow_id == explicit
    assert changeset.changes.properties["subflow_id"] == explicit
  end

  test "a non-UUID subflow_id in properties is an error, not a crash" do
    changeset =
      Node.changeset(%Node{}, %{graph_id: @graph_id, properties: %{"subflow_id" => "nope"}})

    refute changeset.valid?
    assert %{subflow_id: ["is invalid"]} = errors_on(changeset)
  end

  test "graph_id is copied into properties, overwriting a stale copy" do
    changeset =
      Node.changeset(%Node{}, %{
        graph_id: @graph_id,
        properties: %{"label" => "Start", "graph_id" => Ecto.UUID.generate()}
      })

    assert changeset.changes.properties == %{"label" => "Start", "graph_id" => @graph_id}
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
