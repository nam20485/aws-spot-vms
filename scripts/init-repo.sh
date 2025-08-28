#
# called by agent after creating the repo from this template
#

#
# `create-project.md` assigned to agent w/ 2 inputs:
# 1. `project-name` (e.g., `my-project`)
# 2. list of app creation documents
# agent creates repo from this template
# agent copies app creation documents to `docs/` dir
# agent runs this script with `project-name` as argument
#

echo "Initializing the repository..."
# create tracking project, name = "${project-name}-project"
# create issues (TODO: move ``.labels.json`` and ``import-labels.sh`` to this repo)
#  