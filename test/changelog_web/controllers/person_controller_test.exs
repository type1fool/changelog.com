defmodule ChangelogWeb.PersonControllerTest do
  use ChangelogWeb.ConnCase
  use Bamboo.Test

  import Mock

  alias Changelog.{Newsletters, Person, Subscription}

  test "getting a person's page", %{conn: conn} do
    p = insert(:person)
    conn = get(conn, Routes.person_path(conn, :show, p.handle))
    assert html_response(conn, 200) =~ p.name
  end

  describe "joining" do
    test "getting the form", %{conn: conn} do
      conn = get(conn, Routes.person_path(conn, :join))

      assert conn.status == 200
      assert conn.resp_body =~ "form"
    end

    @tag :as_user
    test "getting form when signed in is not allowed", %{conn: conn} do
      conn = get(conn, Routes.person_path(conn, :join))
      assert html_response(conn, 302)
      assert conn.halted
    end

    test "submission with no data redirects", %{conn: conn} do
      conn = post(conn, Routes.person_path(conn, :join))
      assert redirected_to(conn) == Routes.person_path(conn, :join)
    end

    test "submission with missing data re-renders with errors", %{conn: conn} do
      count_before = count(Person)
      conn = post(conn, Routes.person_path(conn, :join), person: %{email: "nope"})
      assert html_response(conn, 200) =~ ~r/wrong/i
      assert count(Person) == count_before
    end

    test "submission with gotcha field filled out re-renders with errors", %{conn: conn} do
      count_before = count(Person)
      conn = post(conn, Routes.person_path(conn, :join), person: %{email: "joe@blow.com", name: "Joe Blow", handle: "joeblow"}, gotcha: "robit here")
      assert html_response(conn, 200) =~ ~r/fishy/i
      assert count(Person) == count_before
    end

    test "submission with qq.com re-renders with errors", %{conn: conn} do
      count_before = count(Person)
      conn = post(conn, Routes.person_path(conn, :join), person: %{email: "joe@qq.com", name: "Joe Blow", handle: "joeblow"})
      assert html_response(conn, 200) =~ ~r/qq.com/i
      assert count(Person) == count_before
    end

    test "submission with required data creates person, sends email, and redirects", %{conn: conn} do
      count_before = count(Person)

      conn = with_mock Craisin.Subscriber, [subscribe: fn(_, _, _) -> nil end] do
        post(conn, Routes.person_path(conn, :join), person: %{email: "joe@blow.com", name: "Joe Blow", handle: "joeblow"})
      end

      person = Repo.one(from p in Person, where: p.email == "joe@blow.com")
      assert_delivered_email ChangelogWeb.Email.community_welcome(person)
      assert redirected_to(conn) == Routes.root_path(conn, :index)
      assert count(Person) == count_before + 1
    end

    test "submission with existing email sends email, redirects, but doesn't create new person", %{conn: conn} do
      existing = insert(:person)
      count_before = count(Person)

      conn = with_mock Craisin.Subscriber, [subscribe: fn(_, _, _) -> nil end] do
        post(conn, Routes.person_path(conn, :join), person: %{email: existing.email, name: "Joe Blow", handle: "joeblow"})
      end

      existing = Repo.one(from p in Person, where: p.email == ^existing.email)

      assert_delivered_email ChangelogWeb.Email.community_welcome(existing)
      assert redirected_to(conn) == Routes.root_path(conn, :index)
      assert count(Person) == count_before
    end
  end

  describe "subscribing in general" do
    test "getting the form", %{conn: conn} do
      conn = get(conn, Routes.person_path(conn, :subscribe))
      assert conn.status == 200
      assert conn.resp_body =~ "form"
    end

    test "submission with gotcha field filled out re-renders with errors", %{conn: conn} do
      count_before = count(Person)
      conn = post(conn, Routes.person_path(conn, :subscribe), email: "joe@blow.com", gotcha: "whoops robot")
      assert redirected_to(conn) == Routes.person_path(conn, :subscribe)
      assert count(Person) == count_before
    end

    test "submission with qq.com email address re-renders with errors", %{conn: conn} do
      count_before = count(Person)
      conn = post(conn, Routes.person_path(conn, :subscribe), email: "joe@qq.com")
      assert redirected_to(conn) == Routes.person_path(conn, :subscribe)
      assert count(Person) == count_before
    end

    test "submission with no data redirects", %{conn: conn} do
      conn = post(conn, Routes.person_path(conn, :subscribe))
      assert redirected_to(conn) == Routes.person_path(conn, :subscribe)
    end
  end

  describe "subscribing to newsletters" do
    test "getting the form", %{conn: conn} do
      conn = get(conn, Routes.person_path(conn, :subscribe, to: "nightly"))
      assert conn.status == 200
      assert conn.resp_body =~ "form"
    end

    test "with required data creates person, subscribes, sends email, redirects", %{conn: conn} do
      with_mock(Craisin.Subscriber, [subscribe: fn(_, _) -> nil end]) do
        count_before = count(Person)

        conn = post(conn, Routes.person_path(conn, :subscribe), email: "joe@blow.com")

        person = Repo.one(from p in Person, where: p.email == "joe@blow.com")

        assert called(Craisin.Subscriber.subscribe(Newsletters.weekly().list_id, :_))
        assert_delivered_email ChangelogWeb.Email.subscriber_welcome(person, Newsletters.weekly())
        assert redirected_to(conn) == Routes.root_path(conn, :index)
        assert count(Person) == count_before + 1
      end
    end

    test "with existing email subscribes, sends email, redirects, but doesn't create person", %{conn: conn} do
      with_mock(Craisin.Subscriber, [subscribe: fn(_, _) -> nil end]) do
        existing = insert(:person)
        count_before = count(Person)

        conn = post(conn, Routes.person_path(conn, :subscribe), email: existing.email, to: "nightly")

        existing = Repo.one(from p in Person, where: p.email == ^existing.email)

        assert called(Craisin.Subscriber.subscribe(Newsletters.nightly().list_id, :_))
        assert_delivered_email ChangelogWeb.Email.subscriber_welcome(existing, Newsletters.nightly())
        assert redirected_to(conn) == Routes.root_path(conn, :index)
        assert count(Person) == count_before
      end
    end
  end

  describe "subscribing to podcasts" do
    test "getting the form", %{conn: conn} do
      podcast = insert(:podcast)
      conn = get(conn, Routes.person_path(conn, :subscribe, to: podcast.slug))
      assert conn.status == 200
      assert conn.resp_body =~ "form"
    end

    test "with required data creates person, subscribes, sends email, redirects", %{conn: conn} do
      podcast = insert(:podcast)
      count_before = count(Person)

      conn = post(conn, Routes.person_path(conn, :subscribe), email: "joe@blow.com", to: podcast.slug)

      person = Repo.one(from p in Person, where: p.email == "joe@blow.com")

      assert_delivered_email ChangelogWeb.Email.subscriber_welcome(person, podcast)
      assert redirected_to(conn) == Routes.root_path(conn, :index)
      assert count(Person) == count_before + 1
      assert count(Subscription) == 1
    end

    test "with existing email subscribes, sends email, redirects, but doesn't create person", %{conn: conn} do
      podcast = insert(:podcast)
      existing = insert(:person)
      count_before = count(Person)

      conn = post(conn, Routes.person_path(conn, :subscribe), email: existing.email, to: podcast.slug)

      existing = Repo.one(from p in Person, where: p.email == ^existing.email)

      assert_delivered_email ChangelogWeb.Email.subscriber_welcome(existing, podcast)
      assert redirected_to(conn) == Routes.root_path(conn, :index)
      assert count(Person) == count_before
      assert count(Subscription) == 1
    end
  end
end
