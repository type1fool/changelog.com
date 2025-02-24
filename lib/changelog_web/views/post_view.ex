defmodule ChangelogWeb.PostView do
  use ChangelogWeb, :public_view

  alias Changelog.{Files, ListKit}
  alias ChangelogWeb.{Endpoint, NewsItemView, PersonView}

  def admin_edit_link(conn, %{admin: true}, post) do
    path = Routes.admin_post_path(conn, :edit, post, next: current_path(conn))
    link("[edit]", to: path, data: [turbolinks: false])
  end
  def admin_edit_link(_, _, _), do: nil

  def guid(post), do: post.guid || "changelog.com/posts/#{post.id}"

  def image_mime_type(post), do: Files.Image.mime_type(post.image)

  def image_path(post, version) do
    {post.image, post}
    |> Files.Image.url(version)
    |> String.replace_leading("/priv", "")
  end

  def image_url(post, version), do: Routes.static_url(Endpoint, image_path(post, version))

  def paragraph_count(post) do
    post
    |> Map.get(:body, "")
    |> md_to_html()
    |> String.split("<p>")
    |> ListKit.compact()
    |> length()
  end

  def url(post, action), do: Routes.post_url(Endpoint, action, post.slug)
end
