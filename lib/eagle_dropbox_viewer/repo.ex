defmodule EagleDropboxViewer.Repo do
  use Ecto.Repo,
    otp_app: :eagle_dropbox_viewer,
    adapter: Ecto.Adapters.SQLite3
end
