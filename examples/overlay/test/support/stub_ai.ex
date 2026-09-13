defmodule Demo.StubAI do
  @moduledoc """
  The `FormFlow.Config.AI` module the Build with AI tests configure in place
  of the real one: it reports what it was asked and answers with whatever the
  test canned.

  Both travel in application env rather than in the process dictionary or a
  `send(self(), ...)`, because `submit/2` does not run in the test's process
  — `start_async/3` spawns a task, so `self()` there is the task and its
  dictionary is empty.
  """

  use FormFlow.Config.AI

  @impl true
  def submit(request, _config) do
    %{pid: pid, answer: answer} = Application.fetch_env!(:demo, :ai_stub)
    send(pid, {:ai_asked, request})
    answer
  end
end
