# Sourced after the plugin bundle is installed and enabled: by pr-preview's
# instance/deploy.sh on a PR preview, and by `make deploy` (through
# build/preview-hook.sh) on the local Docker stack. Both give it the same
# helpers (compose, mmctl, mmctl_on, wait_for_ping) and set $id and $version.
# The preview's server config is fresh every deploy, so keep every step
# idempotent and assume no earlier settings. Put here whatever the plugin needs
# beyond its own bundle: companion plugins, plugin settings, database tweaks.
#
# On a preview this runs from the base branch, so a change here reaches
# previews only after it merges. Run `make deploy` to try it locally first.
#
# Example: set plugin settings through mmctl.
# mmctl config set "PluginSettings.Plugins.${id}.examplesetting" "value" >/dev/null
# echo "configured ${id}"
