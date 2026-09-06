defmodule DemoWeb.BrandingLive.UserSwitchers do
  @moduledoc """
  Scratch directions for the demo's user switcher: the control that picks
  which hardcoded perspective (reviewer, dog owner, cat owner, docs reader)
  the demo is viewed from.

  Each direction is a `switcher/1` clause. The branding page renders every
  one twice, in a mock header and again in page content, since the real
  component will live in both places. Selecting a user here only updates
  the mock; the real control will set a session cookie and reload.
  """

  use DemoWeb, :html

  @users [
    %{
      id: "reviewer",
      name: "Pet License Reviewer",
      short: "Reviewer",
      initials: "PR",
      emoji: "📋",
      icon: "hero-clipboard-document-check",
      blurb: "Reviews and decides license applications",
      role: "staff",
      avatar: "bg-indigo-600",
      dot: "bg-indigo-500",
      soft: "bg-indigo-50 text-indigo-700 ring-indigo-200"
    },
    %{
      id: "dog_owner",
      name: "Dog Owner",
      short: "Dog Owner",
      initials: "DO",
      emoji: "🐶",
      icon: "hero-user",
      blurb: "Applies for and renews a dog license",
      role: "applicant",
      avatar: "bg-fuchsia-600",
      dot: "bg-fuchsia-500",
      soft: "bg-fuchsia-50 text-fuchsia-700 ring-fuchsia-200"
    },
    %{
      id: "cat_owner",
      name: "Cat Owner",
      short: "Cat Owner",
      initials: "CO",
      emoji: "🐱",
      icon: "hero-user",
      blurb: "Applies for and renews a cat license",
      role: "applicant",
      avatar: "bg-violet-600",
      dot: "bg-violet-500",
      soft: "bg-violet-50 text-violet-700 ring-violet-200"
    },
    %{
      id: "docs_reader",
      name: "Docs Reader",
      short: "Docs",
      initials: "DR",
      emoji: "📖",
      icon: "hero-book-open",
      blurb: "Reads the README-style docs at /",
      role: "reader",
      avatar: "bg-gray-700",
      dot: "bg-gray-400",
      soft: "bg-gray-100 text-gray-700 ring-gray-200"
    }
  ]

  @directions [
    %{
      id: :avatar_pill,
      title: "1 · Avatar pill",
      note: "The familiar account-menu shape; the gradient avatar ties it to the mark."
    },
    %{
      id: :viewing_as,
      title: "2 · “Viewing as” label",
      note: "The label carries the meaning, so the value itself can stay quiet."
    },
    %{
      id: :segmented,
      title: "3 · Segmented control",
      note: "All four perspectives visible at once; one click, no menu. Wide."
    },
    %{
      id: :emoji_personas,
      title: "4 · Emoji personas",
      note: "Playful and instantly scannable; the menu is a 2×2 grid of persona tiles."
    },
    %{
      id: :gradient_ring,
      title: "5 · Gradient ring",
      note:
        "Borrows the header's gradient line as a hairline ring, so it reads as brand, not chrome."
    },
    %{
      id: :avatar_stack,
      title: "6 · Avatar stack",
      note: "Shows there are other perspectives before you open it; the menu is persona cards."
    },
    %{
      id: :role_badge,
      title: "7 · Role badge",
      note: "Environment-badge feel: a status dot per role and a mono role tag in the menu."
    },
    %{
      id: :split_button,
      title: "8 · Split button",
      note: "Identity on the left, action on the right; “Switch” is a verb you can see."
    },
    %{
      id: :banner_strip,
      title: "9 · Banner strip",
      note:
        "Impersonation-style strip under the nav; the most prominent, and it explains the state."
    },
    %{
      id: :icon_avatar,
      title: "10 · Icon avatar",
      note: "Smallest footprint; the menu carries the explanation."
    },
    %{
      id: :palette,
      title: "11 · Palette",
      note:
        "A command-palette trigger; rows carry number-key hints for a later keyboard shortcut."
    },
    %{
      id: :perspective_radios,
      title: "12 · Perspective radios",
      note: "A radio list in a dropdown; leans on the form-builder feel of the app."
    },
    %{
      id: :underline_tabs,
      title: "13 · Underline tabs",
      note: "Extends the nav's own vocabulary: four perspectives as a second tab group."
    },
    %{
      id: :dark_avatar_switch,
      title: "14 · Dark avatar + switch",
      note:
        "One dark initials circle with a gradient chevron badge, then “Name · Switch”. #6 and #10 combined."
    },
    %{
      id: :gradient_ring_switch,
      title: "15 · Gradient ring + switch",
      note: "#5 without the eye: “Name · Switch” inside the hairline ring, chevron on the right."
    },
    %{
      id: :dark_avatar_stacked,
      title: "16 · Dark avatar, stacked label",
      note: "#14 with #2's “Viewing as” label over the name; the badge still carries the chevron."
    },
    %{
      id: :gradient_ring_avatar,
      title: "17 · Gradient ring, dark avatar",
      note:
        "#15 with the dark initials circle inside the ring, so the ring and avatar read as one unit."
    },
    %{
      id: :dark_avatar_pill,
      title: "18 · Dark avatar in a pill",
      note:
        "#1's bordered pill carrying the dark avatar and “Name · Switch”; quieter than the gradient ring."
    },
    %{
      id: :dark_avatar_chevron_right,
      title: "19 · Dark avatar, chevron right",
      note:
        "#14 with the verb dropped: bold name and a right chevron, to compare word vs. affordance."
    },
    %{
      id: :built,
      title: "20 · Built: #16 with check badges",
      note:
        "The real DemoWeb.UserSwitcher. The current row's avatar wears a check badge instead of a right-hand tick; choosing a row reloads the page as that user."
    }
  ]

  def users, do: @users
  def user(id), do: Enum.find(@users, &(&1.id == id))
  def directions, do: @directions

  @doc """
  Renders one user-switcher direction.

  `id` must be unique per rendering (the same direction is rendered in the
  header and in content). `current` is the selected user map. Selecting a
  user pushes a `"select"` event with `%{"direction" => ..., "user" => ...}`.
  """
  attr :direction, :atom, required: true
  attr :id, :string, required: true
  attr :current, :map, required: true
  attr :users, :list, default: @users

  attr :align, :atom,
    values: [:start, :end],
    default: :end,
    doc: "which edge a dropdown menu hangs from"

  attr :open, :boolean, default: false, doc: "render a dropdown menu already open"

  def switcher(%{direction: :avatar_pill} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex items-center gap-2 rounded-full border border-gray-200 bg-white py-1 pl-1 pr-3 text-sm font-medium text-gray-900 shadow-xs transition-colors hover:border-gray-300 hover:bg-gray-50">
          <.gradient_avatar user={@current} class="size-7 text-[10px]" />
          {@current.name}
          <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
        </span>
      </:trigger>
      <.menu_rows id={@id} direction={@direction} users={@users} current={@current}>
        <:lead :let={u}><.gradient_avatar user={u} class="size-8 text-[11px]" /></:lead>
      </.menu_rows>
    </.dropdown>
    """
  end

  def switcher(%{direction: :viewing_as} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex flex-col items-start rounded-lg px-3 py-1.5 leading-tight transition-colors hover:bg-gray-100">
          <span class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">
            Viewing as
          </span>
          <span class="inline-flex items-center gap-1 text-sm font-semibold text-gray-900">
            {@current.name}
            <.icon name="hero-chevron-up-down" class="size-4 text-gray-400" />
          </span>
        </span>
      </:trigger>
      <.menu_rows
        id={@id}
        direction={@direction}
        users={@users}
        current={@current}
        heading="Switch perspective"
        footer="Switching reloads the page as that user."
      />
    </.dropdown>
    """
  end

  def switcher(%{direction: :segmented} = assigns) do
    ~H"""
    <div
      id={@id}
      class="inline-flex rounded-lg bg-gray-100 p-1"
      role="radiogroup"
      aria-label="Viewing as"
    >
      <button
        :for={u <- @users}
        type="button"
        role="radio"
        aria-checked={to_string(u.id == @current.id)}
        phx-click={select(@direction, u.id)}
        class={[
          "inline-flex items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
          u.id == @current.id && "bg-white text-indigo-600 shadow-sm",
          u.id != @current.id && "text-gray-600 hover:text-gray-900"
        ]}
      >
        <.icon name={u.icon} class="size-4" />
        {u.short}
      </button>
    </div>
    """
  end

  def switcher(%{direction: :emoji_personas} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open} menu_class="w-72">
      <:trigger>
        <span class="inline-flex items-center gap-2 rounded-full bg-gray-100 py-1 pl-1 pr-3 text-sm font-medium text-gray-900 transition-colors hover:bg-gray-200">
          <span class="inline-flex size-7 items-center justify-center rounded-full bg-white text-base shadow-xs">
            {@current.emoji}
          </span>
          {@current.name}
          <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
        </span>
      </:trigger>
      <div class="rounded-xl border border-gray-200 bg-white p-2 shadow-lg">
        <div class="grid grid-cols-2 gap-1.5">
          <button
            :for={u <- @users}
            type="button"
            phx-click={select(@direction, u.id, @id)}
            class={[
              "flex flex-col items-center gap-1.5 rounded-lg px-2 py-3 text-center transition-colors",
              u.id == @current.id && "bg-indigo-50 ring-1 ring-indigo-200",
              u.id != @current.id && "hover:bg-gray-100"
            ]}
          >
            <span class="text-2xl leading-none">{u.emoji}</span>
            <span class="text-xs font-semibold text-gray-900">{u.name}</span>
          </button>
        </div>
      </div>
    </.dropdown>
    """
  end

  def switcher(%{direction: :gradient_ring} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex rounded-full bg-gradient-to-r from-indigo-600 via-violet-600 to-fuchsia-600 p-px shadow-xs transition-opacity hover:opacity-80">
          <span class="inline-flex items-center gap-2 rounded-full bg-white px-3 py-1.5 text-sm font-medium text-gray-900">
            <.icon name="hero-eye" class="size-4 text-violet-600" />
            {@current.name}
            <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
          </span>
        </span>
      </:trigger>
      <.menu_rows
        id={@id}
        direction={@direction}
        users={@users}
        current={@current}
        heading="Viewing as"
      />
    </.dropdown>
    """
  end

  def switcher(%{direction: :avatar_stack} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open} menu_class="w-80">
      <:trigger>
        <span class="inline-flex items-center gap-2.5 rounded-lg px-2 py-1 transition-colors hover:bg-gray-100">
          <span class="flex -space-x-2">
            <span
              :for={u <- @users}
              class={[
                "inline-flex size-7 items-center justify-center rounded-full text-[10px] font-bold text-white ring-2 ring-white",
                u.avatar,
                u.id == @current.id && "z-10 scale-110 ring-indigo-500",
                u.id != @current.id && "opacity-50"
              ]}
            >
              {u.initials}
            </span>
          </span>
          <span class="text-sm">
            <span class="font-semibold text-gray-900">{@current.name}</span>
            <span class="text-gray-400"> · Switch</span>
          </span>
        </span>
      </:trigger>
      <div class="rounded-xl border border-gray-200 bg-white p-2 shadow-lg">
        <div class="grid grid-cols-2 gap-1.5">
          <button
            :for={u <- @users}
            type="button"
            phx-click={select(@direction, u.id, @id)}
            class={[
              "flex flex-col items-start gap-2 rounded-lg p-3 text-left transition-colors",
              u.id == @current.id && "bg-indigo-50 ring-1 ring-indigo-300",
              u.id != @current.id && "hover:bg-gray-100"
            ]}
          >
            <span class={[
              "inline-flex size-8 items-center justify-center rounded-full text-white",
              u.avatar
            ]}>
              <.icon name={u.icon} class="size-4" />
            </span>
            <span class="text-sm font-semibold text-gray-900">{u.name}</span>
            <span class="text-xs leading-snug text-gray-500">{u.blurb}</span>
          </button>
        </div>
      </div>
    </.dropdown>
    """
  end

  def switcher(%{direction: :role_badge} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex items-center gap-2 rounded-md border border-gray-200 bg-white px-2.5 py-1.5 text-xs font-medium text-gray-900 shadow-xs transition-colors hover:bg-gray-50">
          <span class={["size-2 rounded-full", @current.dot]} />
          {@current.name}
          <.icon name="hero-chevron-down" class="size-3.5 text-gray-400" />
        </span>
      </:trigger>
      <ul class="w-72 rounded-lg border border-gray-200 bg-white p-1 shadow-lg" role="listbox">
        <li :for={u <- @users}>
          <button
            type="button"
            role="option"
            aria-selected={to_string(u.id == @current.id)}
            phx-click={select(@direction, u.id, @id)}
            class={[
              "flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-left text-sm transition-colors hover:bg-gray-100",
              u.id == @current.id && "bg-gray-50 font-medium"
            ]}
          >
            <span class={["size-2 rounded-full", u.dot]} />
            <span class="flex-1 text-gray-900">{u.name}</span>
            <span class="font-mono text-[10px] uppercase tracking-wide text-gray-400">{u.role}</span>
          </button>
        </li>
      </ul>
    </.dropdown>
    """
  end

  def switcher(%{direction: :split_button} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex overflow-hidden rounded-lg border border-gray-200 text-sm shadow-xs">
          <span class="inline-flex items-center gap-2 bg-white px-3 py-1.5 font-medium text-gray-900">
            <span class={[
              "inline-flex size-5 items-center justify-center rounded-full text-white",
              @current.avatar
            ]}>
              <.icon name={@current.icon} class="size-3" />
            </span>
            {@current.name}
          </span>
          <span class="inline-flex items-center gap-1.5 border-l border-gray-200 bg-gray-50 px-3 py-1.5 font-semibold text-indigo-600 transition-colors hover:bg-gray-100">
            <.icon name="hero-arrows-right-left" class="size-4" /> Switch
          </span>
        </span>
      </:trigger>
      <.menu_rows id={@id} direction={@direction} users={@users} current={@current}>
        <:lead :let={u}>
          <span class={[
            "inline-flex size-8 items-center justify-center rounded-full text-white",
            u.avatar
          ]}>
            <.icon name={u.icon} class="size-4" />
          </span>
        </:lead>
      </.menu_rows>
    </.dropdown>
    """
  end

  def switcher(%{direction: :banner_strip} = assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-3 gap-y-1 border-y border-indigo-100 bg-indigo-50/70 px-8 py-2 text-sm text-indigo-950">
      <.icon name="hero-eye" class="size-4 text-indigo-600" />
      <span>
        You're viewing the demo as <span class="font-semibold">{@current.name}</span>
        <span class="text-indigo-900/60">— {String.downcase(@current.blurb)}.</span>
      </span>
      <.dropdown id={@id} align={:end} open={@open} class="ml-auto">
        <:trigger>
          <span class="inline-flex items-center gap-1 rounded-md px-2 py-1 font-semibold text-indigo-700 transition-colors hover:bg-indigo-100">
            Switch user <.icon name="hero-chevron-down" class="size-4" />
          </span>
        </:trigger>
        <.menu_rows id={@id} direction={@direction} users={@users} current={@current} />
      </.dropdown>
    </div>
    """
  end

  def switcher(%{direction: :icon_avatar} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="relative inline-flex" title={"Viewing as #{@current.name}"}>
          <span class="inline-flex size-9 items-center justify-center rounded-full bg-gray-900 text-white transition-colors hover:bg-gray-700">
            <.icon name={@current.icon} class="size-5" />
          </span>
          <span class="absolute -bottom-0.5 -right-0.5 inline-flex size-4 items-center justify-center rounded-full bg-gradient-to-br from-indigo-600 to-fuchsia-600 ring-2 ring-white">
            <.icon name="hero-chevron-up-down" class="size-3 text-white" />
          </span>
        </span>
      </:trigger>
      <.menu_rows
        id={@id}
        direction={@direction}
        users={@users}
        current={@current}
        heading="Viewing as"
        footer="Switching reloads the page as that user."
      >
        <:lead :let={u}>
          <span class="inline-flex size-8 items-center justify-center rounded-full bg-gray-900 text-white">
            <.icon name={u.icon} class="size-4" />
          </span>
        </:lead>
      </.menu_rows>
    </.dropdown>
    """
  end

  def switcher(%{direction: :palette} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open} menu_class="w-80">
      <:trigger>
        <span class="inline-flex w-60 items-center gap-2 rounded-lg border border-gray-200 bg-gray-50 px-3 py-1.5 text-sm text-gray-900 transition-colors hover:border-gray-300 hover:bg-white">
          <.icon name="hero-user-circle" class="size-4 text-gray-400" />
          <span class="flex-1 truncate text-left">{@current.name}</span>
          <kbd class="rounded border border-gray-200 bg-white px-1.5 font-mono text-[10px] text-gray-500">
            switch
          </kbd>
        </span>
      </:trigger>
      <div class="overflow-hidden rounded-xl border border-gray-200 bg-white shadow-lg">
        <div class="flex items-center gap-2 border-b border-gray-100 px-3 py-2 text-xs text-gray-500">
          <.icon name="hero-magnifying-glass" class="size-4" /> Switch perspective…
        </div>
        <ul class="p-1.5" role="listbox">
          <li :for={{u, n} <- Enum.with_index(@users, 1)}>
            <button
              type="button"
              role="option"
              aria-selected={to_string(u.id == @current.id)}
              phx-click={select(@direction, u.id, @id)}
              class={[
                "flex w-full items-center gap-3 rounded-lg px-2.5 py-2 text-left text-sm transition-colors hover:bg-gray-100",
                u.id == @current.id && "bg-indigo-50 text-indigo-700"
              ]}
            >
              <.icon name={u.icon} class="size-4 shrink-0 text-gray-500" />
              <span class="flex-1 font-medium">{u.name}</span>
              <kbd class="rounded border border-gray-200 bg-gray-50 px-1.5 font-mono text-[10px] text-gray-500">
                {n}
              </kbd>
            </button>
          </li>
        </ul>
      </div>
    </.dropdown>
    """
  end

  def switcher(%{direction: :perspective_radios} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open} menu_class="w-72">
      <:trigger>
        <span class="inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-sm text-gray-600 transition-colors hover:bg-gray-100 hover:text-gray-900">
          <.icon name="hero-eye" class="size-4" /> Perspective:
          <span class="font-semibold text-gray-900">{@current.name}</span>
          <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
        </span>
      </:trigger>
      <div class="rounded-xl border border-gray-200 bg-white p-2 shadow-lg">
        <p class="px-2 pb-1.5 pt-1 text-xs font-semibold text-gray-500">Who are you today?</p>
        <label
          :for={u <- @users}
          class="flex cursor-pointer items-start gap-3 rounded-lg px-2 py-2 transition-colors hover:bg-gray-100"
        >
          <input
            type="radio"
            name={@id <> "-perspective"}
            class="radio radio-primary radio-sm mt-0.5"
            checked={u.id == @current.id}
            phx-click={select(@direction, u.id, @id)}
          />
          <span class="min-w-0">
            <span class="block text-sm font-medium text-gray-900">{u.name}</span>
            <span class="block text-xs text-gray-500">{u.blurb}</span>
          </span>
        </label>
        <p class="border-t border-gray-100 px-2 pt-2 text-[11px] text-gray-400">
          Reloads the page as the new user.
        </p>
      </div>
    </.dropdown>
    """
  end

  def switcher(%{direction: :underline_tabs} = assigns) do
    ~H"""
    <div id={@id} class="inline-flex items-center gap-1" role="radiogroup" aria-label="Viewing as">
      <span class="mr-2 text-[10px] font-semibold uppercase tracking-wider text-gray-400">
        Viewing as
      </span>
      <button
        :for={u <- @users}
        type="button"
        role="radio"
        aria-checked={to_string(u.id == @current.id)}
        phx-click={select(@direction, u.id)}
        class={[
          "-mb-px border-b-2 px-2 py-1.5 text-sm font-medium transition-colors",
          u.id == @current.id && "border-indigo-600 text-indigo-600",
          u.id != @current.id &&
            "border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-900"
        ]}
      >
        {u.short}
      </button>
    </div>
    """
  end

  def switcher(%{direction: :dark_avatar_switch} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex items-center gap-2.5 rounded-lg py-1 pl-1 pr-2 transition-colors hover:bg-gray-100">
          <.dark_avatar user={@current} badge />
          <span class="text-sm">
            <span class="font-semibold text-gray-900">{@current.name}</span>
            <span class="text-gray-400"> · Switch</span>
          </span>
        </span>
      </:trigger>
      <.dark_menu id={@id} direction={@direction} users={@users} current={@current} />
    </.dropdown>
    """
  end

  def switcher(%{direction: :gradient_ring_switch} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex rounded-full bg-gradient-to-r from-indigo-600 via-violet-600 to-fuchsia-600 p-px shadow-xs transition-opacity hover:opacity-80">
          <span class="inline-flex items-center gap-1.5 rounded-full bg-white px-3 py-1.5 text-sm">
            <span class="font-semibold text-gray-900">{@current.name}</span>
            <span class="text-gray-400">· Switch</span>
            <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
          </span>
        </span>
      </:trigger>
      <.dark_menu id={@id} direction={@direction} users={@users} current={@current} />
    </.dropdown>
    """
  end

  def switcher(%{direction: :dark_avatar_stacked} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex items-center gap-2.5 rounded-lg py-1 pl-1 pr-2 transition-colors hover:bg-gray-100">
          <.dark_avatar user={@current} badge />
          <span class="flex flex-col leading-tight">
            <span class="text-[10px] font-semibold uppercase tracking-wider text-gray-400">
              Viewing as
            </span>
            <span class="text-sm">
              <span class="font-semibold text-gray-900">{@current.name}</span>
              <span class="text-gray-400"> · Switch</span>
            </span>
          </span>
        </span>
      </:trigger>
      <.dark_menu id={@id} direction={@direction} users={@users} current={@current} />
    </.dropdown>
    """
  end

  def switcher(%{direction: :gradient_ring_avatar} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex rounded-full bg-gradient-to-r from-indigo-600 via-violet-600 to-fuchsia-600 p-px shadow-xs transition-opacity hover:opacity-80">
          <span class="inline-flex items-center gap-2 rounded-full bg-white py-1 pl-1 pr-3 text-sm">
            <.dark_avatar user={@current} class="size-7 text-[10px]" />
            <span class="font-semibold text-gray-900">{@current.name}</span>
            <span class="-ml-0.5 text-gray-400">· Switch</span>
            <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
          </span>
        </span>
      </:trigger>
      <.dark_menu id={@id} direction={@direction} users={@users} current={@current} />
    </.dropdown>
    """
  end

  def switcher(%{direction: :dark_avatar_pill} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex items-center gap-2 rounded-full border border-gray-200 bg-white py-1 pl-1 pr-3 text-sm shadow-xs transition-colors hover:border-gray-300 hover:bg-gray-50">
          <.dark_avatar user={@current} class="size-7 text-[10px]" />
          <span class="font-semibold text-gray-900">{@current.name}</span>
          <span class="-ml-0.5 text-gray-400">· Switch</span>
          <.icon name="hero-chevron-down" class="size-4 text-gray-400" />
        </span>
      </:trigger>
      <.dark_menu id={@id} direction={@direction} users={@users} current={@current} />
    </.dropdown>
    """
  end

  def switcher(%{direction: :dark_avatar_chevron_right} = assigns) do
    ~H"""
    <.dropdown id={@id} align={@align} open={@open}>
      <:trigger>
        <span class="inline-flex items-center gap-2 rounded-lg py-1 pl-1 pr-2 transition-colors hover:bg-gray-100">
          <.dark_avatar user={@current} badge />
          <span class="text-sm font-semibold text-gray-900">{@current.name}</span>
          <.icon name="hero-chevron-right" class="size-4 text-gray-400" />
        </span>
      </:trigger>
      <.dark_menu id={@id} direction={@direction} users={@users} current={@current} />
    </.dropdown>
    """
  end

  def switcher(%{direction: :built} = assigns) do
    ~H"""
    <DemoWeb.UserSwitcher.user_switcher id={@id} current_user={@current} align={@align} open={@open} />
    """
  end

  # -- Shared pieces --------------------------------------------------------

  attr :id, :string, required: true
  attr :align, :atom, default: :end
  attr :open, :boolean, default: false
  attr :class, :string, default: nil
  attr :menu_class, :string, default: nil
  slot :trigger, required: true
  slot :inner_block, required: true

  defp dropdown(assigns) do
    ~H"""
    <details
      id={@id}
      open={@open}
      class={["dropdown", @align == :end && "dropdown-end", @class]}
      phx-click-away={JS.remove_attribute("open")}
    >
      <summary class="cursor-pointer list-none select-none [&::-webkit-details-marker]:hidden">
        {render_slot(@trigger)}
      </summary>
      <div class={["dropdown-content z-30 mt-2", @menu_class]}>
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  attr :id, :string, required: true
  attr :direction, :atom, required: true
  attr :users, :list, required: true
  attr :current, :map, required: true
  attr :heading, :string, default: nil
  attr :footer, :string, default: nil
  slot :lead, doc: "optional avatar rendered before the name; receives the user"

  defp menu_rows(assigns) do
    ~H"""
    <div class="w-72 rounded-xl border border-gray-200 bg-white p-1.5 shadow-lg">
      <p
        :if={@heading}
        class="px-2.5 pb-1 pt-1.5 text-[10px] font-semibold uppercase tracking-wider text-gray-400"
      >
        {@heading}
      </p>
      <ul role="listbox">
        <li :for={u <- @users}>
          <button
            type="button"
            role="option"
            aria-selected={to_string(u.id == @current.id)}
            phx-click={select(@direction, u.id, @id)}
            class={[
              "flex w-full items-center gap-3 rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-gray-100",
              u.id == @current.id && "bg-gray-50"
            ]}
          >
            {render_slot(@lead, u)}
            <span class="min-w-0 flex-1">
              <span class="block text-sm font-medium text-gray-900">{u.name}</span>
              <span class="block truncate text-xs text-gray-500">{u.blurb}</span>
            </span>
            <.icon
              :if={u.id == @current.id}
              name="hero-check"
              class="size-4 shrink-0 text-indigo-600"
            />
          </button>
        </li>
      </ul>
      <p
        :if={@footer}
        class="mt-1 border-t border-gray-100 px-2.5 pb-1 pt-2 text-[11px] text-gray-400"
      >
        {@footer}
      </p>
    </div>
    """
  end

  attr :user, :map, required: true
  attr :class, :string, default: "size-7 text-[10px]"

  defp gradient_avatar(assigns) do
    ~H"""
    <span class={[
      "inline-flex shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-indigo-600 via-violet-600 to-fuchsia-600 font-bold text-white",
      @class
    ]}>
      {@user.initials}
    </span>
    """
  end

  attr :user, :map, required: true
  attr :class, :string, default: "size-8 text-[11px]"
  attr :badge, :boolean, default: false, doc: "overlap a small gradient chevron badge"

  defp dark_avatar(assigns) do
    ~H"""
    <span class="relative inline-flex shrink-0">
      <span class={[
        "inline-flex items-center justify-center rounded-full bg-gray-900 font-bold text-white",
        @class
      ]}>
        {@user.initials}
      </span>
      <span
        :if={@badge}
        class="absolute -bottom-1 -right-1 inline-flex size-4 items-center justify-center rounded-full bg-gradient-to-br from-indigo-600 to-fuchsia-600 ring-2 ring-white"
      >
        <%!-- Inline rather than the masked heroicon: a "V" is top-heavy, so the
        path sits 1.5 units below the box's centre to look centred (heroicons'
        mini chevron does the same), and the stroke is heavier than heroicons'
        1.5 to survive a 12px render. --%>
        <svg
          viewBox="0 0 16 16"
          class="size-3 text-white"
          fill="none"
          stroke="currentColor"
          stroke-width="2.25"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M4 7.5l4 4 4-4" />
        </svg>
      </span>
    </span>
    """
  end

  attr :id, :string, required: true
  attr :direction, :atom, required: true
  attr :users, :list, required: true
  attr :current, :map, required: true

  defp dark_menu(assigns) do
    ~H"""
    <.menu_rows id={@id} direction={@direction} users={@users} current={@current} heading="Viewing as">
      <:lead :let={u}><.dark_avatar user={u} /></:lead>
    </.menu_rows>
    """
  end

  # Pushes the selection; when a dropdown id is given, closes it too.
  defp select(direction, user_id, dropdown_id \\ nil) do
    js = JS.push("select", value: %{direction: direction, user: user_id})
    if dropdown_id, do: JS.remove_attribute(js, "open", to: "##{dropdown_id}"), else: js
  end
end
