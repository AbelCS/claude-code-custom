# installed_for($here; $main): the plugins in installed_plugins.json that a project
# has, each { id, name, installPath }. A plugin installed for a project, with scope
# project or local, counts only for that project, recorded under its folder, or under
# the main checkout for a worktree. name is the id without its marketplace, so any
# marketplace's copy counts. Errors on a registry that isn't the expected shape.
# Shared by hook-session-start.sh and setup/tools.sh: jq -L <this folder>, then
# include "installed-plugins".
def installed_for($here; $main):
  .plugins | to_entries | map(
    .key as $id
    | [.value[] | select((.scope != "project" and .scope != "local")
        or .projectPath == $here or .projectPath == $main)] as $copies
    | select($copies | length > 0)
    | {id: $id, name: ($id | split("@")[0]), installPath: ($copies[0].installPath // "")});
