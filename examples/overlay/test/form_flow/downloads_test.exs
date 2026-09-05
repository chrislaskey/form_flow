defmodule Demo.FormFlowDownloadsTest do
  @moduledoc """
  Exercises the download and print routes against a real database, a real
  router, and a real request — the whole path the library's own tests can't
  reach: a mounted route, a position resolved out of the URL, the pinned
  definition parsed, and a file coming back.

  What it holds the library to is that a download says the same thing the
  page it was started from says. The Show page renders the pinned definition
  filled in with the instance's `data`; so does the file, through the same
  `FormFlow.Web.Instances.Forms.Shared.resolve/1`. A test that only checked
  the bytes were a PDF would pass while the two drifted apart.
  """

  use DemoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias FormFlow.Data.Instances
  alias FormFlow.Data.Repo, as: FormFlowRepo
  alias FormFlow.Data.Templates.Flow
  alias FormFlow.Data.Templates.Flows
  alias FormFlow.Data.Templates.Forms
  alias FormFlow.Web.Downloads

  describe "the download route" do
    test "sends the answers as a PDF the browser saves", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      conn = get(conn, Downloads.download_path(instance.id, [form.id]))

      assert response_content_type(conn, :pdf) =~ "application/pdf"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ ~s(filename="application-only.pdf")
      assert String.starts_with?(conn.resp_body, "%PDF-1.4")
    end

    test "the file carries the question as the definition asks it, and the answer", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      conn = get(conn, Downloads.download_path(instance.id, [form.id]))

      assert conn.resp_body =~ "(Name) Tj"
      assert conn.resp_body =~ "(Ada Lovelace) Tj"
      assert conn.resp_body =~ "(Only) Tj"
      assert conn.resp_body =~ "(Application) Tj"
    end

    test "an in-progress form downloads what has been filled in so far", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      {:ok, _started} = Instances.Forms.update_status(instance, [form.id], :in_progress)

      conn = get(conn, Downloads.download_path(instance.id, [form.id]))

      assert conn.status == 200
      assert conn.resp_body =~ "(Status: In progress) Tj"
    end
  end

  describe "the print route" do
    test "sends the same bytes, inline, so the browser opens rather than saves", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      downloaded = get(conn, Downloads.download_path(instance.id, [form.id]))
      printed = get(conn, Downloads.print_path(instance.id, [form.id]))

      assert [disposition] = get_resp_header(printed, "content-disposition")
      assert disposition =~ "inline"
      assert response_content_type(printed, :pdf) =~ "application/pdf"

      # The PDF's creation stamp is the only thing that differs between two
      # renders of one form
      assert scrub(printed.resp_body) == scrub(downloaded.resp_body)
    end
  end

  describe "what a download refuses" do
    test "a flow instance that does not exist", %{conn: conn} do
      conn = get(conn, Downloads.download_path(Ecto.UUID.generate(), [Ecto.UUID.generate()]))

      assert conn.status == 404
      assert conn.resp_body =~ "This flow no longer exists."
    end

    test "a position nobody has opened — there are no answers to print", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()

      conn = get(conn, Downloads.download_path(instance.id, [form.id]))

      assert conn.status == 404
      assert conn.resp_body =~ "hasn't been started yet"
    end

    test "a position the flow does not have", %{conn: conn} do
      %{instance: instance} = flow_of_one()

      conn = get(conn, Downloads.download_path(instance.id, [Ecto.UUID.generate()]))

      assert conn.status == 404
    end
  end

  describe "the link on the form's page" do
    test "the Show page points at both routes, so the file is one click away", %{conn: conn} do
      %{instance: instance, form: form} = flow_of_one()
      complete(instance, [form.id], %{"name" => "Ada Lovelace"})

      {:ok, _view, html} = live(conn, "/users/#{instance.id}/forms/#{form.id}")

      assert html =~ ~s(href="#{Downloads.download_path(instance.id, [form.id])}")
      assert html =~ ~s(href="#{Downloads.print_path(instance.id, [form.id])}")
    end

    test "a page with nothing filled in offers neither — there is nothing to take away", %{
      conn: conn
    } do
      %{instance: instance, form: form} = flow_of_one()

      {:ok, _view, html} = live(conn, "/users/#{instance.id}/forms/#{form.id}")

      refute html =~ Downloads.download_path(instance.id, [form.id])
    end
  end

  # ── fixtures ────────────────────────────────────────────────────────────

  # The demo's own PDF stamp moves every render; everything else must match
  defp scrub(pdf), do: String.replace(pdf, ~r/\/CreationDate \(D:[^)]*\)/, "")

  defp flow_of_one do
    {:ok, flow} = Flows.create(%{name: "Application"})

    start = build_node(flow, ["Start"], "Start")
    only = build_node(flow, ["Form"], "Only", %{form_id: published_form("Only").id})

    edge(flow, start, only)

    {:ok, instance} = Instances.Flows.create(%{flow_id: flow.id, user_id: "demo-user"})

    %{flow: flow, instance: instance, form: only}
  end

  defp complete(instance, path, data) do
    {:ok, _opened} = Instances.Forms.update_status(instance, path, :in_progress)
    {:ok, completed} = Instances.Forms.update_status(instance, path, :completed, data: data)

    completed
  end

  defp build_node(flow, labels, label, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{flow_id: flow.id, labels: labels, properties: %{"data" => %{"label" => label}}},
        attrs
      )

    {:ok, node} = FormFlowRepo.insert(Flow.Node.changeset(%Flow.Node{}, attrs))

    node
  end

  defp edge(flow, source, target) do
    {:ok, _relationship} =
      FormFlowRepo.insert(
        Flow.Relationship.changeset(%Flow.Relationship{}, %{
          flow_id: flow.id,
          source_id: source.id,
          target_id: target.id,
          label: "CONNECTS_TO"
        })
      )
  end

  defp published_form(name) do
    {:ok, form} = Forms.create(%{name: "#{name} #{System.unique_integer([:positive])}"})

    [draft] = form.versions
    definition = %{"elements" => [%{"type" => "text", "name" => "name", "title" => "Name"}]}

    {:ok, draft} = Forms.update_draft(draft, %{definition: definition})
    {:ok, _published} = Forms.update_status(draft, :published)

    form
  end
end
