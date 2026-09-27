defmodule AskroomWeb.JoinHTML do
  @moduledoc """
  Renders the audience join form (`AskroomWeb.JoinController`).
  """

  use AskroomWeb, :html

  embed_templates "join_html/*"
end
