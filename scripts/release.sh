#!/usr/bin/env bash

app_name="AbbrEx"
bundle_id="com.unamatasanatarai.abbrex"
build_dir="build"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/abbrex"
mkdir -p "$cache_dir"
if [[ $? -ne 0 ]]; then
	printf '%s\n' "Error: Failed to create cache directory ${cache_dir}" >&2
	exit 1
fi

dry_run=0
target_version=""

for arg in "$@"; do
	case "$arg" in
	--dry-run)
		dry_run=1
		;;
	*)
		if [[ -z "$target_version" ]]; then
			target_version="$arg"
		fi
		;;
	esac
done

current_version=""
if [[ -f "VERSION" ]]; then
	IFS= read -r current_version <"VERSION"
elif [[ -f "../VERSION" ]]; then
	IFS= read -r current_version <"../VERSION"
fi
current_version="${current_version//[[:space:]]/}"
if [[ -z "$current_version" ]]; then
	current_version="1.0.0"
fi

if [[ -n "$target_version" ]]; then
	target_version="${target_version#v}"
	if [[ ! "$target_version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
		printf '%s\n' "Error: Invalid version format '${target_version}'. Expected format like 1.1.0" >&2
		exit 1
	fi
	new_version="$target_version"

	git rev-parse "v${new_version}" >/dev/null 2>&1
	if [[ $? -eq 0 ]]; then
		printf '%s\n' "Error: Git tag 'v${new_version}' already exists locally" >&2
		exit 1
	fi

	remote_file="${cache_dir}/remote_check.tmp"
	git ls-remote --tags origin "refs/tags/v${new_version}" >"$remote_file" 2>/dev/null
	remote_check=""
	if [[ -f "$remote_file" ]]; then
		IFS= read -r remote_check <"$remote_file"
		rm -f "$remote_file"
	fi
	if [[ -n "$remote_check" ]]; then
		printf '%s\n' "Error: Git tag 'v${new_version}' already exists on remote origin" >&2
		exit 1
	fi
else
	major="${current_version%%.*}"
	rest="${current_version#*.}"
	if [[ "$rest" != "$current_version" && "$rest" =~ \. ]]; then
		minor="${rest%%.*}"
		patch="${rest#*.}"
	elif [[ "$rest" != "$current_version" ]]; then
		minor="$rest"
		patch="0"
	else
		minor="0"
		patch="0"
	fi

	if [[ "$patch" =~ ^[0-9]+$ ]]; then
		patch=$((patch + 1))
		new_version="${major}.${minor}.${patch}"
	else
		new_version="${current_version}.1"
	fi

	tags_file="${cache_dir}/local_tags.tmp"
	git tag -l >"$tags_file" 2>/dev/null
	existing_local_tags=""
	if [[ -f "$tags_file" ]]; then
		while IFS= read -r line; do
			existing_local_tags="${existing_local_tags} ${line}"
		done <"$tags_file"
		rm -f "$tags_file"
	fi

	remote_tags_file="${cache_dir}/remote_tags.tmp"
	git ls-remote --tags origin >"$remote_tags_file" 2>/dev/null
	existing_remote_tags=""
	if [[ -f "$remote_tags_file" ]]; then
		while IFS= read -r line; do
			existing_remote_tags="${existing_remote_tags} ${line}"
		done <"$remote_tags_file"
		rm -f "$remote_tags_file"
	fi

	while [[ "$existing_local_tags" =~ (^|[[:space:]])v${new_version}($|[[:space:]]) ]] || [[ "$existing_remote_tags" =~ refs/tags/v${new_version}($|[[:space:]]) ]]; do
		patch=$((patch + 1))
		new_version="${major}.${minor}.${patch}"
	done
fi

version="$new_version"
dmg_name="AbbrEx-${version}.dmg"
dmg_path="${build_dir}/${dmg_name}"

if [[ "$dry_run" -eq 1 ]]; then
	printf '%s\n' "Previewing release AbbrEx v${version} (bumped from v${current_version})"
	printf '%s\n' "Would run unit test suite (./scripts/test.sh)"
	printf '%s\n' "Would commit version bump to VERSION and push to branch"
	printf '%s\n' "Would build styled DMG package (${dmg_path})"
else
	printf '%s\n' "$version" >"VERSION"

	./scripts/test.sh
	if [[ $? -ne 0 ]]; then
		printf '%s\n' "Error: Test suite execution failed" >&2
		exit 1
	fi

	git diff --quiet "VERSION"
	if [[ $? -ne 0 ]]; then
		git add "VERSION"
		git commit -m "chore(release): bump version to v${version}"
		if [[ $? -ne 0 ]]; then
			printf '%s\n' "Error: Failed to commit version bump" >&2
			exit 1
		fi
		branch_file="${cache_dir}/current_branch.tmp"
		git rev-parse --abbrev-ref HEAD >"$branch_file" 2>/dev/null
		current_branch=""
		if [[ -f "$branch_file" ]]; then
			IFS= read -r current_branch <"$branch_file"
			rm -f "$branch_file"
		fi
		if [[ -z "$current_branch" ]]; then
			printf '%s\n' "Error: Failed to determine current git branch" >&2
			exit 1
		fi
		git push origin "$current_branch"
		if [[ $? -ne 0 ]]; then
			printf '%s\n' "Error: Failed to push commit to remote" >&2
			exit 1
		fi
	fi

	./scripts/build_dmg.sh
	if [[ $? -ne 0 ]]; then
		printf '%s\n' "Error: DMG build failed" >&2
		exit 1
	fi
fi

if [[ -n "$GITHUB_TOKEN" ]]; then
	gh auth status >/dev/null 2>&1
	if [[ $? -ne 0 ]]; then
		unset GITHUB_TOKEN
	fi
fi

prev_tag=""
git rev-parse "v${current_version}" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
	prev_tag="v${current_version}"
else
	prev_tag_file="${cache_dir}/prev_tag.tmp"
	git describe --tags --abbrev=0 >"$prev_tag_file" 2>/dev/null
	if [[ -f "$prev_tag_file" ]]; then
		IFS= read -r prev_tag <"$prev_tag_file"
		rm -f "$prev_tag_file"
	fi
fi

commit_log_target=""
if [[ -n "$prev_tag" ]]; then
	commit_log_target="${prev_tag}..HEAD"
fi

log_file="${cache_dir}/git_log.tmp"
if [[ -n "$commit_log_target" ]]; then
	git log "$commit_log_target" --pretty=format:"%s (%h)" >"$log_file" 2>/dev/null
else
	git log --pretty=format:"%s (%h)" >"$log_file" 2>/dev/null
fi

commit_lines=()
if [[ -f "$log_file" ]]; then
	mapfile -t commit_lines <"$log_file"
	rm -f "$log_file"
fi

features=""
fixes=""
other=""

for line in "${commit_lines[@]}"; do
	if [[ -z "$line" || "$line" =~ ^chore\(release\):\ bump\ version ]]; then
		continue
	fi
	if [[ "$line" =~ ^feat(\([^\)]+\))?:\ (.*)\ \(([a-f0-9]+)\)$ ]]; then
		scope="${BASH_REMATCH[1]}"
		msg="${BASH_REMATCH[2]}"
		hash="${BASH_REMATCH[3]}"
		if [[ -n "$scope" ]]; then
			scope_clean="${scope#\(}"
			scope_clean="${scope_clean%\)}"
			features="${features}* **${scope_clean}**: ${msg} (${hash})"$'\n'
		else
			features="${features}* ${msg} (${hash})"$'\n'
		fi
	elif [[ "$line" =~ ^fix(\([^\)]+\))?:\ (.*)\ \(([a-f0-9]+)\)$ ]]; then
		scope="${BASH_REMATCH[1]}"
		msg="${BASH_REMATCH[2]}"
		hash="${BASH_REMATCH[3]}"
		if [[ -n "$scope" ]]; then
			scope_clean="${scope#\(}"
			scope_clean="${scope_clean%\)}"
			fixes="${fixes}* **${scope_clean}**: ${msg} (${hash})"$'\n'
		else
			fixes="${fixes}* ${msg} (${hash})"$'\n'
		fi
	else
		other="${other}* ${line}"$'\n'
	fi
done

release_notes="## AbbrEx v${version}"$'\n'

if [[ -n "$features" ]]; then
	release_notes="${release_notes}"$'\n'"### Features & Enhancements"$'\n'"${features}"
fi

if [[ -n "$fixes" ]]; then
	release_notes="${release_notes}"$'\n'"### Bug Fixes"$'\n'"${fixes}"
fi

if [[ -n "$other" ]]; then
	release_notes="${release_notes}"$'\n'"### Other Changes"$'\n'"${other}"
fi

if [[ -z "$features" && -z "$fixes" && -z "$other" ]]; then
	if [[ ${#commit_lines[@]} -gt 0 ]]; then
		release_notes="${release_notes}"$'\n'"### Commits"$'\n'
		for line in "${commit_lines[@]}"; do
			release_notes="${release_notes}* ${line}"$'\n'
		done
	else
		release_notes="${release_notes}"$'\n'"Maintenance release."$'\n'
	fi
fi

if [[ -n "$prev_tag" ]]; then
	release_notes="${release_notes}"$'\n'"---"$'\n'"Diff compared to ${prev_tag}. Built with native Swift for macOS 12.0+."
else
	release_notes="${release_notes}"$'\n'"---"$'\n'"Built with native Swift for macOS 12.0+."
fi

if [[ "$dry_run" -eq 1 ]]; then
	printf '%s\n' "Release dry run preview:"
	printf '%s\n' "Version to release: v${version} (bumped from v${current_version})"
	printf '%s\n' "Tag to create: v${version}"
	printf '%s\n' "DMG Package: ${dmg_path} (would be built)"
	printf '%s\n' "Target Bundle: ${bundle_id}"
	printf '%s\n' "Release Notes:"
	printf '%s\n' "$release_notes"
	printf '%s\n' "Command line: gh release create v${version} '${dmg_path}' --title '${app_name} v${version}' --notes <notes>"
else
	git tag -a "v${version}" -m "Release ${app_name} v${version}"
	if [[ $? -ne 0 ]]; then
		printf '%s\n' "Error: Failed to create git tag" >&2
		exit 1
	fi

	git push origin "v${version}"
	if [[ $? -ne 0 ]]; then
		printf '%s\n' "Error: Failed to push git tag to origin" >&2
		exit 1
	fi

	if command -v gh >/dev/null 2>&1; then
		gh release create "v${version}" "${dmg_path}" --title "${app_name} v${version}" --notes "$release_notes"
		if [[ $? -ne 0 ]]; then
			printf '%s\n' "Error: Failed to create GitHub release via gh" >&2
			exit 1
		fi
	else
		printf '%s\n' "Warning: GitHub CLI (gh) not found. Created DMG at ${dmg_path} and tag v${version}." >&2
	fi

	printf '%s\n' "Release v${version} published successfully"
fi
