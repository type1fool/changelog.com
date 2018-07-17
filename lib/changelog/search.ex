defmodule Changelog.Search do
  defmodule Page do
    defstruct items: [], total_entries: 0, page_number: 0, total_pages: 1
  end

  alias Changelog.{NewsItem, Repo}

  def search(query, opts \\ []) do
    opts = Keyword.merge(opts, [attributesToRetrieve: "ObjectID"])
    case Algolia.search(namespace(), query, opts) do
      {:ok, response} -> results_from(response)
      _else -> []
    end
  end

  defp results_from(response) do
    item_ids =
      response
      |> Map.get("hits")
      |> Enum.map(fn(x) -> Map.get(x, "objectID") end)
      |> Enum.map(&String.to_integer/1)

    items = NewsItem
    |> NewsItem.by_ids(item_ids)
    |> NewsItem.preload_all
    |> Repo.all
    |> Enum.map(&NewsItem.load_object/1)

    %Page{
      items: items,
      total_pages: Map.get(response, "nbPages", 1),
      total_entries: Map.get(response, "nbHits", 0),
      page_number: Map.get(response, "page", 0)
    }
  end

  defp namespace, do: "#{Mix.env}_news_items"
end
