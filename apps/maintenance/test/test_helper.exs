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

ExUnit.start()
