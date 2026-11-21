# The token is read when it is used, so tests that build authenticated URLs need one.
System.put_env("GITHUB_ACCESS_TOKEN", "test-token")

# Keep the developer's own account and Git identity out of the tests.
System.put_env(%{
  "GITHUB_ACCOUNT" => "some-account",
  "GIT_AUTHOR_NAME" => "Test",
  "GIT_AUTHOR_EMAIL" => "test@example.com",
  "GIT_COMMITTER_NAME" => "Test",
  "GIT_COMMITTER_EMAIL" => "test@example.com"
})

# A request that no Req.Test stub answers fails the test instead of reaching the network.
Req.default_options(
  plug: fn conn -> raise "unstubbed request to #{conn.host}#{conn.request_path}" end,
  retry: false
)

# The test cache is inside this repository. Git must never mistake it for a checkout and run
# its commands on the repository around it.
System.put_env("GIT_CEILING_DIRECTORIES", Maintenance.cache_path())

ExUnit.start()
