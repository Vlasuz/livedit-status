# LiveEdit AI Agent — status checks

Every 10 minutes GitHub Actions checks that the service works for a customer:
the API health endpoint (database, disk, configuration, backups), the plans
used by the plugin, the product page, the plugin download, and that the TLS
certificates have at least 14 days left. A failed run emails the repository
owner.
