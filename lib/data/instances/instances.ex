defmodule FormFlow.Data.Instances do
  @moduledoc """
  `FormFlow.Data.Instances` module captures what users produce by going
  through the flows `FormFlow.Data.Templates` defines — the instance side of
  each template concept: `FormFlow.Data.Instances.Flow` to
  `FormFlow.Data.Templates.Flow`, `FormFlow.Data.Instances.Form` to
  `FormFlow.Data.Templates.Form`.

  ## Journeys

  An instance of a *whole* root flow — the `FormFlow.Data.Instances.Flow` row
  together with every `FormFlow.Data.Instances.Form` filled at a position
  inside it, however deep the subflow tree goes — is what these docs call a
  **journey**.

  The word is shorthand — nothing is named "journey" in the schema — and the
  docs here use it freely, so it is worth grounding once: "flow instance"
  alone reads as one step's worth of work, where what is usually meant is the
  entire traversal, the root flow instance and everything hanging off it.
  Where only the row itself is meant, these docs say so.

  Traversal state is never stored. `FormFlow.Data.Instances.FlowProgress`
  derives it from the live template tree and the journey's form instances, so
  a template edit cannot desync it.
  """
end
