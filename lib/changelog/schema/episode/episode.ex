defmodule Changelog.Episode do
  use Changelog.Schema, default_sort: :published_at

  alias Changelog.{EpisodeHost, EpisodeGuest, EpisodeRequest, EpisodeTopic,
                   EpisodeStat, EpisodeSponsor, Files, NewsItem, Notifier,
                   Podcast, Regexp, Transcripts}
  alias ChangelogWeb.{EpisodeView, TimeView}

  defenum Type, full: 0, bonus: 1, trailer: 2

  schema "episodes" do
    field :slug, :string
    field :guid, :string

    field :title, :string
    field :subtitle, :string
    field :type, Type

    field :featured, :boolean, default: false
    field :highlight, :string
    field :subhighlight, :string

    field :summary, :string
    field :notes, :string

    field :published, :boolean, default: false
    field :published_at, :utc_datetime
    field :recorded_at, :utc_datetime
    field :recorded_live, :boolean, default: false

    field :audio_file, Files.Audio.Type
    field :bytes, :integer
    field :duration, :integer

    field :download_count, :float
    field :import_count, :float
    field :reach_count, :integer

    field :transcript, {:array, :map}

    belongs_to :podcast, Podcast
    belongs_to :episode_request, EpisodeRequest, foreign_key: :request_id

    has_many :episode_hosts, EpisodeHost, on_delete: :delete_all
    has_many :hosts, through: [:episode_hosts, :person]
    has_many :episode_guests, EpisodeGuest, on_delete: :delete_all
    has_many :guests, through: [:episode_guests, :person]
    has_many :episode_topics, EpisodeTopic, on_delete: :delete_all
    has_many :topics, through: [:episode_topics, :topic]
    has_many :episode_sponsors, EpisodeSponsor, on_delete: :delete_all
    has_many :sponsors, through: [:episode_sponsors, :sponsor]
    has_many :episode_stats, EpisodeStat, on_delete: :delete_all

    timestamps()
  end

  def distinct_podcast(query),                       do: from(q in query, distinct: q.podcast_id)
  def featured(query \\ __MODULE__),                 do: from(q in query, where: q.featured == true)
  def next_after(query \\ __MODULE__, episode),      do: from(q in query, where: q.published_at > ^episode.published_at)
  def previous_to(query \\ __MODULE__, episode),     do: from(q in query, where: q.published_at < ^episode.published_at)
  def published(query \\ __MODULE__),                do: from(q in query, where: q.published, where: q.published_at <= ^Timex.now)
  def recorded_between(query, start_time, end_time), do: from(q in query, where: q.recorded_at <= ^start_time, where: q.end_time < ^end_time)
  def recorded_future_to(query, time),               do: from(q in query, where: q.recorded_at > ^time)
  def recorded_live(query \\ __MODULE__),            do: from(q in query, where: q.recorded_live == true)
  def scheduled(query \\ __MODULE__),                do: from(q in query, where: q.published, where: q.published_at > ^Timex.now)
  def search(query, term),                           do: from(q in query, where: fragment("search_vector @@ plainto_tsquery('english', ?)", ^term))
  def unpublished(query \\ __MODULE__),              do: from(q in query, where: not(q.published))
  def top_reach_first(query \\ __MODULE__),          do: from(q in query, order_by: [desc: :reach_count])
  def with_ids(query \\ __MODULE__, ids),            do: from(q in query, where: q.id in ^ids)
  def with_numbered_slug(query \\ __MODULE__),       do: from(q in query, where: fragment("slug ~ E'^\\\\d+$'"))
  def with_slug(query \\ __MODULE__, slug),          do: from(q in query, where: q.slug == ^slug)

  def with_podcast_slug(query \\ __MODULE__, slug)
  def with_podcast_slug(query, nil),  do: query
  def with_podcast_slug(query, slug), do: from(q in query, join: p in Podcast, where: q.podcast_id == p.id, where: p.slug == ^slug)

  def full(query \\ __MODULE__),    do: from(q in query, where: q.type == ^:full)
  def bonus(query \\ __MODULE__),   do: from(q in query, where: q.type == ^:bonus)
  def trailer(query \\ __MODULE__), do: from(q in query, where: q.type == ^:trailer)

  def exclude_transcript(query \\ __MODULE__) do
    fields = __MODULE__.__schema__(:fields) |> Enum.reject(&(&1 == :transcript))
    from(q in query, select: ^fields)
  end

  def has_transcript(%{transcript: nil}), do: false
  def has_transcript(%{transcript: []}), do: false
  def has_transcript(_), do: true

  def is_public(episode, as_of \\ Timex.now) do
    is_published(episode) && Timex.before?(episode.published_at, as_of)
  end

  def is_published(episode), do: episode.published

  def is_publishable(episode) do
    validated =
      change(episode, %{})
      |> validate_required([:slug, :title, :published_at, :summary, :audio_file])
      |> validate_format(:slug, Regexp.slug, message: Regexp.slug_message)
      |> unique_constraint(:slug, name: :episodes_slug_podcast_id_index)
      |> cast_assoc(:episode_hosts)

    validated.valid? && !is_published(episode)
  end

  def admin_changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:slug, :title, :subtitle, :published, :featured, :request_id,
                     :highlight, :subhighlight, :summary, :notes, :published_at,
                     :recorded_at, :recorded_live, :guid, :type])
    |> cast_attachments(params, [:audio_file])
    |> validate_required([:slug, :title, :published, :featured])
    |> validate_format(:slug, Regexp.slug, message: Regexp.slug_message)
    |> validate_published_has_published_at()
    |> unique_constraint(:slug, name: :episodes_slug_podcast_id_index)
    |> cast_assoc(:episode_hosts)
    |> cast_assoc(:episode_guests)
    |> cast_assoc(:episode_sponsors)
    |> cast_assoc(:episode_topics)
    |> derive_bytes_and_duration()
  end

  def get_news_item(episode) do
    episode
    |> NewsItem.with_episode()
    |> Repo.one()
  end

  def load_news_item(episode) do
    item = episode |> get_news_item() |> NewsItem.load_object(episode)
    Map.put(episode, :news_item, item)
  end

  def object_id(episode), do: "#{episode.podcast_id}:#{episode.id}"

  def participants(episode) do
    episode =
      episode
      |> preload_guests()
      |> preload_hosts()

    episode.guests ++ episode.hosts
  end

  def preload_all(episode) do
    episode
    |> preload_podcast()
    |> preload_topics()
    |> preload_guests()
    |> preload_hosts()
    |> preload_sponsors()
  end

  def preload_episode_request(query = %Ecto.Query{}), do: Ecto.Query.preload(query, :episode_request)
  def preload_episode_request(episode), do: Repo.preload(episode, :episode_request)

  def preload_hosts(query = %Ecto.Query{}) do
    query
    |> Ecto.Query.preload(episode_hosts: ^EpisodeHost.by_position)
    |> Ecto.Query.preload(:hosts)
  end
  def preload_hosts(episode) do
    episode
    |> Repo.preload(episode_hosts: {EpisodeHost.by_position, :person})
    |> Repo.preload(:hosts)
  end

  def preload_guests(query = %Ecto.Query{}) do
    query
    |> Ecto.Query.preload(episode_guests: ^EpisodeGuest.by_position)
    |> Ecto.Query.preload(:guests)
  end
  def preload_guests(episode) do
    episode
    |> Repo.preload(episode_guests: {EpisodeGuest.by_position, :person})
    |> Repo.preload(:guests)
  end

  def preload_podcast(nil), do: nil
  def preload_podcast(query = %Ecto.Query{}), do: Ecto.Query.preload(query, :podcast)
  def preload_podcast(episode), do: Repo.preload(episode, :podcast)

  def preload_sponsors(query = %Ecto.Query{}) do
    query
    |> Ecto.Query.preload(episode_sponsors: ^EpisodeSponsor.by_position)
    |> Ecto.Query.preload(:sponsors)
  end
  def preload_sponsors(episode) do
    episode
    |> Repo.preload(episode_sponsors: {EpisodeSponsor.by_position, :sponsor})
    |> Repo.preload(:sponsors)
  end

  def preload_topics(query = %Ecto.Query{}) do
    query
    |> Ecto.Query.preload(episode_topics: ^EpisodeTopic.by_position)
    |> Ecto.Query.preload(:topics)
  end
  def preload_topics(episode) do
    episode
    |> Repo.preload(episode_topics: {EpisodeTopic.by_position, :topic})
    |> Repo.preload(:topics)
  end

  def update_stat_counts(episode) do
    stats = Repo.all(assoc(episode, :episode_stats))

    new_downloads =
      stats
      |> Enum.map(&(&1.downloads))
      |> Enum.sum
      |> Kernel.+(episode.import_count)
      |> Kernel./(1)
      |> Float.round(2)

    new_reach =
      stats
      |> Enum.map(&(&1.uniques))
      |> Enum.sum

    episode
    |> change(%{download_count: new_downloads, reach_count: new_reach})
    |> Repo.update!()
  end

  def update_notes(episode, text) do
    episode
    |> change(notes: text)
    |> Repo.update!()
  end

  def update_transcript(episode, text) do
    parsed = Transcripts.Parser.parse_text(text, participants(episode))

    updated =
      episode
      |> change(transcript: parsed)
      |> Repo.update!()

    if !has_transcript(episode) && has_transcript(updated) do
      Task.start_link(fn -> Notifier.notify(updated) end)
    end

    updated
  end

  defp derive_bytes_and_duration(changeset) do
    if new_audio_file = get_change(changeset, :audio_file) do
      tagged_file = EpisodeView.audio_local_path(%{changeset.data | audio_file: new_audio_file})

      case File.stat(tagged_file) do
        {:ok, stats} ->
          seconds = extract_duration_seconds(tagged_file)
          change(changeset, bytes: stats.size, duration: seconds)
        {:error, _} -> changeset
      end
    else
      changeset
    end
  end

  defp extract_duration_seconds(path) do
    try do
      {info, _exit_code} = System.cmd("ffmpeg", ["-i", path], stderr_to_stdout: true)
      [_match, duration] = Regex.run ~r/Duration: (.*?),/, info
      TimeView.seconds(duration)
    catch
      _all -> 0
    end
  end

  defp validate_published_has_published_at(changeset) do
    published = get_field(changeset, :published)
    published_at = get_field(changeset, :published_at)

    if published && is_nil(published_at) do
      add_error(changeset, :published_at, "can't be blank when published")
    else
      changeset
    end
  end
end
