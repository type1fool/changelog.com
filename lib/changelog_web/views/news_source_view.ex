defmodule ChangelogWeb.NewsSourceView do
  use ChangelogWeb, :public_view

  alias Changelog.Files.Icon
  alias Changelog.NewsSource
  alias ChangelogWeb.{Endpoint, NewsItemView}

  def admin_edit_link(conn, %{admin: true}, source) do
    path = Routes.admin_news_source_path(conn, :edit, source, next: current_path(conn))
    link("[edit]", to: path, data: [turbolinks: false])
  end
  def admin_edit_link(_, _, _), do: nil

  def icon_path(news_source, version) do
    {news_source.icon, news_source}
    |> Icon.url(version)
    |> String.replace_leading("/priv", "")
  end

  def icon_url(news_source), do: icon_url(news_source, :small)
  def icon_url(news_source, version) do
    if news_source.icon do
      Routes.static_url(Endpoint, icon_path(news_source, version))
    else
      "/images/defaults/avatar-source.png"
    end
  end

  def news_count(topic), do: NewsSource.news_count(topic)
end
