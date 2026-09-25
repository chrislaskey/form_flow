defmodule DemoWeb.ExperienceEntry do
  @moduledoc """
  `on_mount` hook that puts a visitor into the side of the demo they just
  opened: if the current user is not one the page is for
  (`DemoWeb.Experiences.fits?/2`), the demo's current user becomes the
  page's `lands_on` before the page renders.

  So the reviews page is read by the reviewer and the admin pages by the
  admin, whoever clicked, and the header's menus can offer every side to
  everyone without any of them leading to a refusal.

  ## Why it leaves LiveView to do it

  Who the demo is viewing as lives in the session, and a LiveView cannot
  write the session - it is fixed when the socket is built. So a mismatch
  is answered with an ordinary `redirect/2` to `GET /view-as/:user_id`
  (`DemoWeb.UserSwitchController.show/2`), which writes the session and
  sends the visitor back to where they were going. One full page load, on
  the click that changes sides and no other: the hook runs on every mount,
  and a visitor already on the right side costs one comparison.

  Because it is a redirect rather than a filter, it works the same however
  the page was reached - a menu click, a bookmark, a link someone pasted
  into chat. That is why it lives here and not in the menu's links.

  Where it sends them back to is the experience's path plus the route's
  `*path` splat, so a deep link into one journey or one form survives the
  switch. A query string does not: it is mixed in with the path params by
  the time this runs, and nothing in the demo deep-links with one.

  ## Use

      use DemoWeb, :live_view

      on_mount {DemoWeb.ExperienceEntry, :user}

  The argument is the experience's id (`DemoWeb.Experiences`). It runs
  after `DemoWeb.UserHook`, which is what puts `:current_user` there to be
  read - a `live_session`'s own `on_mount` runs before a view's.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias DemoWeb.Experiences

  def on_mount(experience_id, params, _session, socket) do
    experience = Experiences.fetch!(experience_id)

    if Experiences.fits?(experience, socket.assigns.current_user) do
      {:cont, assign(socket, :experience, experience)}
    else
      {:halt, redirect(socket, to: switch_path(experience, params))}
    end
  end

  defp switch_path(experience, params) do
    return_to = Path.join([experience.path | splat(params)])

    "/view-as/#{experience.lands_on}?return_to=#{URI.encode_www_form(return_to)}"
  end

  # The route's `*path` segments, and nothing when the view is mounted
  # outside a router (`:not_mounted_at_router`) or the page has none
  defp splat(%{"path" => segments}) when is_list(segments), do: segments
  defp splat(_params), do: []
end
