defmodule Changelog.SlackControllerTest do
  use Changelog.ConnCase

  describe "the countdown robot" do
    setup do
      {:ok, conn: build_conn(), podcast: insert(:podcast, name: "Go Time", slug: "gotime")}
    end

    test "it works when no episode is found", %{conn: conn, podcast: podcast} do
      conn = get(conn, slack_path(conn, :countdown, podcast.slug))
      assert conn.status == 200
      assert conn.resp_body =~ "There aren't any"
    end

    test "it uses the closest upcoming episode", %{conn: conn, podcast: podcast} do
      insert(:live_episode, podcast: podcast, recorded_at: hours_from_now(3))
      insert(:live_episode, podcast: podcast, recorded_at: hours_from_now(24*3))
      conn = get(conn, slack_path(conn, :countdown, podcast.slug))
      assert conn.status == 200
      assert conn.resp_body =~ "There's only"
    end

    test "it uses an episode that is currently recording", %{conn: conn, podcast: podcast} do
      insert(:live_episode, podcast: podcast, recorded_at: hours_ago(1))
      conn = get(conn, slack_path(conn, :countdown, podcast.slug))
      assert conn.status == 200
      assert conn.resp_body =~ "It's noOOoOow GO TIME!"
    end

    test "it doesn't use non Go Time episodes", %{conn: conn, podcast: podcast} do
      insert(:live_episode, recorded_at: hours_from_now(24*9))
      conn = get(conn, slack_path(conn, :countdown, podcast.slug))
      assert conn.status == 200
      assert conn.resp_body =~ "There aren't any"
    end
  end

  describe "the event endpoint" do
    setup do
      conn = Plug.Conn.put_req_header(build_conn(), "accept", "application/json")
      {:ok, conn: conn}
    end

    test "it responds to verification challenge", %{conn: conn} do
      conn = post(conn, slack_path(conn, :event, %{
        "type" => "url_verification",
        "token" => "Jhj5dZrVaK7ZwHHjRyZWjbDl",
        "challenge" => "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P"
      }))

      assert json_response(conn, 200) == %{"challenge" => "3eZbrw1aBm2rZgRNFdxV2595E9CY3gmdALWMmHkvFXO7tYXAYM8P"}
    end

    test "it responds to the team_join event", %{conn: conn} do
      conn = post(conn, slack_path(conn, :event, %{
        "type" => "event_callback",
        "event" => %{
          "type" => "team_join",
          "user" => %{
            "id" => "U2XU53R",
            "name" => "@gracehopper"
          }
        }

      }))

      assert conn.status == 200
    end

    test "it responds with method not allowed for unsupported events", %{conn: conn} do
      conn = post(conn, slack_path(conn, :event, %{"type" => "event_callback", "event" => %{"type" => "channel_join"}}))

      assert conn.status == 405
    end
  end
end
