#!/bin/sh

# This script prepares a virtual environment, installs the requisite python dependencies, runs the generate_analytics python script (which updates the docs/jekyll site with the new analytics data), pushes that regenerated static content to the repo specified in $GIT_REMOTE, and cleans up the virtual environment.
# How to run (assumes working directory is /scripts): `bash ./build_and_push.sh`.
#   Note: Assumes the following:
#     The working directory is /scripts.
#     The user has appropriate credentials to push to their git remote.
#     The git repo is configured correctly such that it is tracking the specified git remote.
#     Both the git repo and the git remote are configured correctly such that they are tracking the specified git branch.
#     Dependencies (`sh` (could be an alias to ex. `bash`), `python3`, `rm`, and `git`) are installed and internet access is available (to install additional python dependencies and push to the git remote).
#   Note: The following environment variables can be supplied to override their default values:
#     PYTHON=$(command -v python3) # path to python3 executable
#     GIT_REMOTE=origin # name of the remote (can list all remotes using `git remote -v`)
#     GIT_BRANCH=master # name of the branch (can list all branches using `git branch -av` - this branch should be listed at least twice as it needs to be available locally and remotely)
#     GIT_USER_NAME="Build and Push Automation Script" # name to use for the committer/author; order of operations will be user provided variable, already configured committer identity, the default specified here
#     GIT_USER_EMAIL="<>" # email to use for the committer/author; order of operations will be user provided variable, already configured committer identity, the default specified here (no email associated)
#     GIT_COMMIT_MESSAGE="Automated commit to rebuild the static site" # message to use on commit - recommended that this is provided when COMMIT_ENTIRE_REPO is 'true'
#     COMMIT_ENTIRE_REPO=true # by default, commit all changes in the repo, otherwise only commit changes in /docs

set -o errexit # exit on non-zero exit code
set -o nounset # exit on unbound variable
set -o pipefail # don't hide errors within pipes

_python="${PYTHON:-"$(command -v python3)"}"
if ! [ -x "$(command -v "$_python")" ]; then
  echo "'python3' is not installed or is not executable by current user..."
  echo "Quitting..."
  exit 1
fi
echo "Python executable: $_python, Python version: $("$_python" -V)"

echo "Setting up virtual environment..."
"$_python" -m venv venv

echo "Activating virtual environment..."
source ./venv/bin/activate

echo "Installing dependencies in virtual environment..."
python -m pip install -r ./requirements.txt

_rm_does_not_exist=1
if ! [ -x "$(command -v rm)" ] ; then
  _rm_does_not_exist=0
  echo "'rm' is not installed or is not executable by current user..."
  echo "Cannot clean up /docs/analytics..."
  echo "There is a potential for unwanted analyses to still show up on the site even after having deleted them from /analytics..."
  echo "You might want to do a manual review of /docs/analytics to ensure only the desired analyses are there..."
else
  echo "Cleaning up /docs/analytics..."
  rm -r ../docs/analytics
fi

echo "Running \`generate_analytics.py\` and regenerating /docs/analytics..."
python ./generate_analytics.py

echo "Deactivating virtual environment..."
deactivate

if ! [ -x "$(command -v git)" ]; then
  echo "'git' is not installed or is not executable by current user..."
  echo "Quitting..."
  exit 1
fi
_git_remote="${GIT_REMOTE:-"origin"}"
_git_branch="${GIT_BRANCH:-"master"}"
_git_user_name="${GIT_USER_NAME:-""}"
if [ -z "$_git_user_name" ]; then
  if git config user.name; then
    _git_user_name="$(git config user.name)"
    if [ -z "$_git_user_name" ]; then
      _git_user_name="Build and Push Automation Script"
    fi
  else
    _git_user_name="Build and Push Automation Script"
  fi
fi
_git_user_email="${GIT_USER_EMAIL:-""}"
if [ -z "$_git_user_email" ]; then
  if git config user.email; then
    _git_user_email="$(git config user.email)"
    if [ -z "$_git_user_email" ]; then
      _git_user_email="<>"
    fi
  else
    _git_user_email="<>"
  fi
fi
_git_commit_message="${GIT_COMMIT_MESSAGE:-"Automated commit to rebuild the static site"}"
echo "Git executable: $(command -v git), Git version: $(git --version)"
echo "Git remote: $_git_remote, Git branch: $_git_branch"
echo "Git user name: $_git_user_name, Git user email: $_git_user_email"
echo "Git commit message: $_git_commit_message"
# TODO: be able to determine calling location and adjust accordingly, run other generate scripts

echo "Checking if git branch exists locally..."
if git show-ref --quiet --heads "$_git_branch"; then
  echo "Git branch exists locally..."
else
  echo "Git branch doesn't exist locally..."
  echo "Quitting..."
  exit 1
fi

_commit_entire_repo="${COMMIT_ENTIRE_REPO:-"true"}"
_changes_path="../"
if ! [ "$_commit_entire_repo" = "true" ]; then
  _changes_path="../docs"
fi

if [ "$_commit_entire_repo" = "true" ]; then
  echo "Checking if repo had changes..."
else
  echo "Checking if /docs had changes..."
fi
if git diff --quiet "$_git_branch" -- "$_changes_path"; then
  echo "No changes detected..."
  echo "Quitting..."
  exit 1
else
  echo "Changes detected..."
fi

echo "Checking if git remote exists and is reachable and if git branch exists on it..."
if git ls-remote --heads "$_git_remote" "$_git_branch" > /dev/null 2>&1 ; then
  echo "Git remote and git branch are available..."
else
  echo "Git remote and/or branch are unavailable..."
  echo "Quitting..."
  exit 1
fi

if [ "$_commit_entire_repo" = "true" ]; then
  echo "Staging all changes..."
else
  echo "Staging changes in /docs..."
fi
git add "$_changes_path"
if [ "$_commit_entire_repo" = "true" ]; then
  git restore --staged ./venv # don't ever want to add the virtual environment, esp since it's intentionally temporary
fi

echo "Committing changes..."
git -c user.name="$_git_user_name" -c user.email="$_git_user_email" commit --allow-empty-message -m "$_git_commit_message"

echo "Pushing changes..."
git push "$_git_remote" "$_git_branch"

if _rm_does_not_exist ; then
  echo "'rm' is not installed or is not executable by current user..."
  echo "Cannot clean up virtual environment..."
else
  echo "Cleaning up virtual environment..."
  rm -r ./venv
fi

echo "Build and push succeeded..."
echo "Quitting..."
