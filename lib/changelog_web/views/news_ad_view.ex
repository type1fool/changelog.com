defmodule ChangelogWeb.NewsAdView do
  use ChangelogWeb, :public_view

  alias Changelog.{Files, NewsAd}
  alias ChangelogWeb.{Endpoint, SponsorView}

  def admin_edit_link(conn, %{admin: true}, ad) do
    path = Routes.admin_news_sponsorship_path(conn, :edit, ad.sponsorship, next: current_path(conn))
    content_tag(:span, class: "news_item-toolbar-meta-item") do
      [
        link("(#{ad.click_count}/#{ad.impression_count})", to: path, data: [turbolinks: false])
      ]
    end
  end
  def admin_edit_link(_, _, _), do: nil

  def image_link(ad, version \\ :large) do
    if ad.image do
      content_tag :div, class: "news_item-image" do
        link to: ad.url, data: [news: true] do
          tag(:img, src: image_url(ad, version), alt: ad.headline)
        end
      end
    end
  end

  def image_path(ad, version) do
    {ad.image, ad}
    |> Files.Image.url(version)
    |> String.replace_leading("/priv", "")
  end

  def image_url(ad, version), do: Routes.static_url(Endpoint, image_path(ad, version))

  def render_toolbar_button(_conn, _ad), do: nil
end
