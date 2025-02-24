defmodule ChangelogWeb.Admin.PostControllerTest do
  use ChangelogWeb.ConnCase

  alias Changelog.Post

  @valid_attrs %{title: "Ruby on Rails", slug: "ruby-on-rails", author_id: 42}
  @invalid_attrs %{title: "Ruby on Rails", slug: "", author_id: 42}

  @tag :as_inserted_admin
  test "lists published posts and all draft posts", %{conn: conn} do
    t1 = insert(:published_post)
    t2 = insert(:post, author: conn.assigns.current_user)
    t3 = insert(:post)

    conn = get(conn, Routes.admin_post_path(conn, :index))

    assert html_response(conn, 200) =~ ~r/Posts/
    assert String.contains?(conn.resp_body, t1.title)
    assert String.contains?(conn.resp_body, t2.title)
    assert String.contains?(conn.resp_body, t3.title)
  end

  @tag :as_inserted_editor
  test "lists published posts and my draft posts", %{conn: conn} do
    t1 = insert(:published_post)
    t2 = insert(:post, author: conn.assigns.current_user)
    t3 = insert(:post)

    conn = get(conn, Routes.admin_post_path(conn, :index))

    assert html_response(conn, 200) =~ ~r/Posts/
    assert String.contains?(conn.resp_body, t1.title)
    assert String.contains?(conn.resp_body, t2.title)
    refute String.contains?(conn.resp_body, t3.title)
  end

  @tag :as_admin
  test "renders form to create new post", %{conn: conn} do
    conn = get(conn, Routes.admin_post_path(conn, :new))
    assert html_response(conn, 200) =~ ~r/new/
  end

  @tag :as_admin
  test "creates post and redirects", %{conn: conn} do
    author = insert(:person)
    conn = post(conn, Routes.admin_post_path(conn, :create), post: %{@valid_attrs | author_id: author.id})

    created = Repo.one(Post.limit(1))
    assert redirected_to(conn) == Routes.admin_post_path(conn, :edit, created)
    assert count(Post) == 1
  end

  @tag :as_admin
  test "does not create with invalid attributes", %{conn: conn} do
    count_before = count(Post)
    conn = post(conn, Routes.admin_post_path(conn, :create), post: @invalid_attrs)

    assert html_response(conn, 200) =~ ~r/error/
    assert count(Post) == count_before
  end

  @tag :as_admin
  test "renders form to edit post", %{conn: conn} do
    post = insert(:post)

    conn = get(conn, Routes.admin_post_path(conn, :edit, post))
    assert html_response(conn, 200) =~ ~r/edit/i
  end

  @tag :as_admin
  test "updates post and redirects", %{conn: conn} do
    author = insert(:person)
    post = insert(:post, author: author)

    conn = put(conn, Routes.admin_post_path(conn, :update, post.id), post: %{@valid_attrs | author_id: author.id})

    assert redirected_to(conn) == Routes.admin_post_path(conn, :index)
    assert count(Post) == 1
  end

  @tag :as_admin
  test "does not update with invalid attributes", %{conn: conn} do
    post = insert(:post)
    count_before = count(Post)

    conn = put(conn, Routes.admin_post_path(conn, :update, post.id), post: @invalid_attrs)

    assert html_response(conn, 200) =~ ~r/error/
    assert count(Post) == count_before
  end

  @tag :as_inserted_admin
  test "publishes a post", %{conn: conn} do
    post = insert(:publishable_post)

    conn = post(conn, Routes.admin_post_path(conn, :publish, post))

    assert redirected_to(conn) == Routes.admin_post_path(conn, :index)
    assert count(Post.published()) == 1
  end

  @tag :as_admin
  test "unpublishes a post", %{conn: conn} do
    post = insert(:published_post)

    conn = post(conn, Routes.admin_post_path(conn, :unpublish, post))

    assert redirected_to(conn) == Routes.admin_post_path(conn, :index)
    assert count(Post.published()) == 0
  end

  test "requires user auth on all actions", %{conn: conn} do
    post = insert(:post)

    Enum.each([
      get(conn, Routes.admin_post_path(conn, :index)),
      get(conn, Routes.admin_post_path(conn, :new)),
      post(conn, Routes.admin_post_path(conn, :create), post: @valid_attrs),
      get(conn, Routes.admin_post_path(conn, :edit, post.id)),
      put(conn, Routes.admin_post_path(conn, :update, post.id), post: @valid_attrs),
      delete(conn, Routes.admin_post_path(conn, :delete, post.id)),
    ], fn conn ->
      assert html_response(conn, 302)
      assert conn.halted
    end)
  end
end
