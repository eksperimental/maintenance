import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :maintenance_web, MaintenanceWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "j8gD0aUfFPeVOOeCXaZPck6kCaAb1PCWaBujJvWpkSpIQ2owfaz+zZUZXkrVqaOx",
  server: false
