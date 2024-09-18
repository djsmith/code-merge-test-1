#
# Script to test alternative branching to resolve merge conflicts between main, develop,
# feature and release branches.
#
# The normal workflow for working with 'feature' branches is to start a Pull Request in
# Github to merge the given feature branch into the 'develop' branch. This allows other
# developers to review the code before it is deployed to the Dev environment for QA
# and client review.
# Unfortunately when there are merge conflicts between the 'develop' branch (from
# changes made via other feature branches) and the new feature branch, Github expects
# to merge the 'develop' branch into the 'feature' branch when resolving the conflicts.
# This results in changes to the 'feature' branch that are not relevant to that feature
# and will cause unrelated code changes to be merged into a 'release' branch that
# shouldn’t be there.
# We need an alternative way to resolve merge conflicts, but still have the ability
# to review code changes via a Pull Request and have those changes deployed to the
# Dev environment.
#

Param(
    [Parameter(Mandatory = $true, HelpMessage = 'URL to remote repository, which should be empty.')]
    [ValidateScript({
            if ($_ -match "github\.com") {
                $true
            } else {
                throw "This script is designed for use with GitHub."
            }
        })]
    [string]$RepoUrl,
    [Parameter(HelpMessage = 'Pauses the script to allow the user to inspect progress.')]
    [switch]$StepByStep
)

# Pauses script execution based on the global $StepByStep switch.
function Step-ByStep {
    param (
        [string]$Message
    )

    if ($StepByStep) {
        if ($Message) {
            Write-Host "`n*** $Message ***" -ForegroundColor Yellow
        }
        Write-Host "Press Enter to continue" -ForegroundColor Yellow
        Read-Host
    }
}

# Execute a Git command using Start-Process.
function Invoke-GitCommand {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    Write-Host -Object "`nExecuting: git $Command" -ForegroundColor Green

    Start-Process git -ArgumentList $Command -NoNewWindow -Wait

    # Pause script to allow other Git tools to release locks
    Start-Sleep -Seconds 2
}

# Create Pull Request on GitHub using the given parameters in the URL.
function Open-GithubPullRequest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Target,
        [switch]$WarnToNotComplete
    )

    if ($WarnToNotComplete) {
        Write-Warning -Message "This PR will have a merge conflict between '$Source' and '$Target' and SHOULD NOT be completed.`nPress Enter to continue"
    } else {
        Write-Host -Object "`nPlease complete a PR to merge '$Source' into '$Target' branch.`nPress Enter to continue" -ForegroundColor Green
    }
    Start-Sleep -Seconds 3

    Start-Process "https://github.com/djsmith/code-merge-test-1/compare/$Target...$($Source)?expand=1"
    Read-Host
}

# Add timestamp to string value parameter with a '{0}' placeholder.
function Add-TimeStamp {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return $Value -f $(Get-Date -Format '[yyyy-MM-dd hh:mm:sstt]')
}


# Delete .git folder and markdown files.
Remove-Item -Recurse -Force ".git" -ErrorAction SilentlyContinue
Remove-Item -Force "*.md" -ErrorAction SilentlyContinue

# Initialize git repo
Invoke-GitCommand "init --initial-branch main"

$readme = 'README.md'
# Create 'README.md' file with intro content, commit changes.
Set-Content -Path $readme -Value "# Project Introduction"
Invoke-GitCommand "add -A"
Invoke-GitCommand 'commit -m "Add README.md with intro content"'
Step-ByStep

# Merge 'develop' branch into 'main' branch.
Invoke-GitCommand "switch --create develop"
Step-ByStep

# Add remote and test if it is empty before pushing any code.
Invoke-GitCommand "remote add origin $RepoUrl"
if (git ls-remote --heads origin) {
    throw "The remote repository '$RepoUrl' is not empty."
}

# Push repo to origin, both branches with upstream tracking.
Invoke-GitCommand "push -u origin main"
Invoke-GitCommand "push -u origin develop"
Step-ByStep

# Create 'feature/f1' branch from the 'main' branch, add 'f1.md' file, update 'README.md', commit changes, push to 'origin'.
$newFeature = 'feature/f1'
Invoke-GitCommand "switch --create $newFeature main"
Set-Content -Path "$($newFeature.split('/')[1]).md" -Value (Add-TimeStamp -Value "# $newFeature {0}")
Add-Content -Path $readme -Value (Add-TimeStamp -Value "`n## $newFeature {0}")
Invoke-GitCommand "add -A"
Invoke-GitCommand "commit -m `"Add $newFeature`""
Invoke-GitCommand "push -u origin $newFeature"
Step-ByStep

# Create a PR to merge 'feature/f1' branch into 'develop' branch.
Open-GithubPullRequest -Source $newFeature -Target 'develop'

# Wait for user to complete PR, then fetch latest changes into 'develop' branch.
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"

# Create 'release/r1' branch from the 'main' branch.
$newRelease = 'release/r1'
Invoke-GitCommand "switch --create $newRelease main"

# Merge 'feature/f1' branch into 'release/r1' branch, update 'README.md' file, commit changes, and push to 'origin'.
Invoke-GitCommand "merge $newFeature"
Add-Content -Path $readme -Value (Add-TimeStamp -Value "`n## $newRelease {0}")
Invoke-GitCommand "add -A"
Invoke-GitCommand "commit -m `"Add $newRelease`""
Invoke-GitCommand "push -u origin $newRelease"
Step-ByStep

# Create PR for 'release/r1' branch into the 'main' branch and wait for user to complete.
Open-GithubPullRequest -Source $newRelease -Target 'main'

# Pull latest changes into 'main' branch, add tag, and push to 'origin'.
Invoke-GitCommand "switch main"
Invoke-GitCommand "pull"
Invoke-GitCommand "tag -a $($newRelease.split('/')[1]) -m `"$newRelease`""
Invoke-GitCommand "push --tags"
Step-ByStep

# Create a PR for 'main' branch into the 'develop' branch and wait for user to complete.
Open-GithubPullRequest -Source 'main' -Target 'develop'

# Pull latest changes into 'develop' branch.
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"
Step-ByStep

# Create 'feature/f2' branch from the 'main' branch, add 'f2.md' file, update 'README.md', commit changes, push to 'origin'.
$newFeature = 'feature/f2'
Invoke-GitCommand "switch --create $newFeature main"
Set-Content -Path "$($newFeature.split('/')[1]).md" -Value (Add-TimeStamp -Value "# $newFeature {0}")
Add-Content -Path $readme -Value (Add-TimeStamp -Value "`n## $newFeature {0}")
Invoke-GitCommand "add -A"
Invoke-GitCommand "commit -m `"Add $newFeature`""
Invoke-GitCommand "push -u origin $newFeature"
Step-ByStep

# Create 'feature/f3' branch from the 'main' branch, add 'f3.md' file, update 'README.md', commit changes, push to 'origin'.
$previousFeature = $newFeature
$newFeature = 'feature/f3'
Invoke-GitCommand "switch --create $newFeature main"
Set-Content -Path "$($newFeature.split('/')[1]).md" -Value (Add-TimeStamp -Value "# $newFeature {0}")
Add-Content -Path $readme -Value (Add-TimeStamp -Value "`n## $newFeature {0}")
Invoke-GitCommand "add -A"
Invoke-GitCommand "commit -m `"Add $newFeature`""
Invoke-GitCommand "push -u origin $newFeature"
Step-ByStep

# Create a PR to merge 'feature/f3' branch into 'develop' branch and wait for user to complete.
Open-GithubPullRequest -Source $newFeature -Target 'develop'

# Pull latest changes into 'develop' branch.
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"
Step-ByStep

# Create a PR to merge 'feature/f2' branch into 'develop' branch which should not be merged because of a conflict.
Open-GithubPullRequest -Source $previousFeature -Target 'develop' -WarnToNotComplete

# Create a temporary 'merge-conflict' branch for 'feature/f2', push to 'origin'
$newFeature = 'feature/f2-merge-conflict'
Invoke-GitCommand "switch --create $newFeature $previousFeature"
Invoke-GitCommand "push -u origin $newFeature"
Step-ByStep

# Create a PR to merge 'feature/f2-merge-conflict' branch into 'develop' branch and wait for user to complete.
Open-GithubPullRequest -Source $newFeature -Target 'develop'

# Pull latest changes into 'develop' branch
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"
Step-ByStep

# Delete the 'feature/f2-merge-conflict' branch from 'origin' and local repos.
Invoke-GitCommand "push --delete origin $newFeature"
Invoke-GitCommand "branch --delete $newFeature"

# Create 'release/r2' branch from the 'main' branch.
$newRelease = 'release/r2'
Invoke-GitCommand "switch --create $newRelease main"

# Merge 'feature/f2' branch into 'release/r2' branch, update 'README.md' file, commit changes, and push to 'origin'.
$newFeature = 'feature/f2'
Invoke-GitCommand "merge $newFeature"
Add-Content -Path $readme -Value (Add-TimeStamp -Value "`n## $newRelease {0}")
Invoke-GitCommand "add -A"
Invoke-GitCommand "commit -m `"Add $newRelease`""
Invoke-GitCommand "push -u origin $newRelease"
Step-ByStep

# Before 'release/r2' is merged with 'main', create 'feature/f4' branch from the 'main' branch,
# add 'f4.md' file, update 'README.md', commit changes, push to 'origin'
$newFeature = 'feature/f4'
Invoke-GitCommand "switch --create $newFeature main"
Set-Content -Path "$($newFeature.split('/')[1]).md" -Value (Add-TimeStamp -Value "# $newFeature {0}")
Add-Content -Path $readme -Value (Add-TimeStamp -Value "`n## $newFeature {0}")
Invoke-GitCommand "add -A"
Invoke-GitCommand "commit -m `"Add $newFeature`""
Invoke-GitCommand "push -u origin $newFeature"
Step-ByStep

# Create a PR to merge 'feature/f4' branch into 'develop' branch and wait for user to complete.
Open-GithubPullRequest -Source $newFeature -Target 'develop' -WarnToNotComplete

# Create a temporary 'merge-conflict' branch for 'feature/f4', push to 'origin'
$previousFeature = $newFeature
$newFeature = 'feature/f4-merge-conflict'
Invoke-GitCommand "switch --create $newFeature $previousFeature"
Invoke-GitCommand "push -u origin $newFeature"
Step-ByStep

# Create a PR to merge 'feature/f4-merge-conflict' branch into 'develop' branch and wait for user to complete.
Open-GithubPullRequest -Source $newFeature -Target 'develop'

# Pull latest changes into 'develop' branch.
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"
Step-ByStep

# Delete the 'feature/f2-merge-conflict' branch from 'origin' and local repos.
Invoke-GitCommand "push --delete origin $newFeature"
Invoke-GitCommand "branch --delete $newFeature"



# Create PR for 'release/r2' branch into the 'main' branch and wait for user to complete.
Open-GithubPullRequest -Source $newRelease -Target 'main'

# Pull latest changes into 'main' branch, add tag, and push to 'origin'.
Invoke-GitCommand "switch main"
Invoke-GitCommand "pull"
Invoke-GitCommand "tag -a $($newRelease.split('/')[1]) -m `"$newRelease`""
Invoke-GitCommand "push --tags"
Step-ByStep



# Create a PR for 'main' branch into the 'develop' branch which should not be merged because of a conflict.
# - This was caused by a change made in 'release/r2', not in 'feature/f2' or 'feature/f3'.
Open-GithubPullRequest -Source 'main' -Target 'develop' -WarnToNotComplete

# todo; Can cherry-pick be useful here or anywhere else?

# Create temporary branch to resolve merge conflict with 'develop' without merging into the 'main' branch.
$mainMergeConflict = 'main-develop-merge-conflict'
Invoke-GitCommand "switch --create $mainMergeConflict main"
Invoke-GitCommand "push -u origin $mainMergeConflict"
Step-ByStep

# Create a PR to merge 'main-develop-merge-conflict' branch into 'develop' branch and wait for user to complete.
Open-GithubPullRequest -Source $mainMergeConflict -Target 'develop'

# Pull latest changes into the 'main-develop-merge-conflict' branch
Invoke-GitCommand "pull"

# Pull latest changes into 'develop' branch
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"
Step-ByStep

# Delete the 'main-develop-merge-conflict' branch from 'origin' and local repos.
Invoke-GitCommand "push --delete origin $mainMergeConflict"
Invoke-GitCommand "branch --delete $mainMergeConflict"



# Create temporary branch to resolve merge conflict with 'feature/f4' without merging into the 'main' branch.
$mainMergeConflict = 'main-f4-merge-conflict'
$previousFeature = 'feature/f4'
Invoke-GitCommand "switch --create $mainMergeConflict main"
Invoke-GitCommand "push -u origin $mainMergeConflict"
Step-ByStep

# Create a PR to merge 'main-f4-merge-conflict' branch into 'feature/f4' branch and wait for user to complete.
Open-GithubPullRequest -Source $mainMergeConflict -Target $previousFeature

# Pull latest changes into the 'main-f4-merge-conflict' branch
Invoke-GitCommand "pull"

# Pull latest changes into 'develop' branch
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"

# Pull latest changes into 'feature/f4' branch
Invoke-GitCommand "switch $previousFeature"
Invoke-GitCommand "pull"
Step-ByStep

# Delete the 'main-f4-merge-conflict' branch from 'origin' and local repos.
Invoke-GitCommand "push --delete origin $mainMergeConflict"
Invoke-GitCommand "branch --delete $mainMergeConflict"



# Create temporary branch to resolve merge conflict with 'feature/f3' without merging into the 'main' branch.
$mainMergeConflict = 'main-f3-merge-conflict'
$previousFeature = 'feature/f3'
Invoke-GitCommand "switch --create $mainMergeConflict main"
Invoke-GitCommand "push -u origin $mainMergeConflict"
Step-ByStep

# Create a PR to merge 'main-f3-merge-conflict' branch into 'feature/f3' branch and wait for user to complete.
Open-GithubPullRequest -Source $mainMergeConflict -Target $previousFeature

# Pull latest changes into the 'main-f3-merge-conflict' branch
Invoke-GitCommand "pull"

# Pull latest changes into 'develop' branch
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"

# Pull latest changes into 'feature/f3' branch
Invoke-GitCommand "switch $previousFeature"
Invoke-GitCommand "pull"
Step-ByStep

# Delete the 'main-f3-merge-conflict' branch from 'origin' and local repos.
Invoke-GitCommand "push --delete origin $mainMergeConflict"
Invoke-GitCommand "branch --delete $mainMergeConflict"



# Add more changes to 'feature/f3' and push to 'origin'
Add-Content -Path "$($previousFeature.split('/')[1]).md" -Value (Add-TimeStamp -Value "`n# $previousFeature {0}")
Add-Content -Path $readme -Value (Add-TimeStamp -Value "`n## $previousFeature {0}")
Invoke-GitCommand "add -A"
Invoke-GitCommand "commit -m `"Change $previousFeature`""
Invoke-GitCommand "push origin"
Step-ByStep

# Create temp branch for 'feature/f3-merge-conflict' to 'develop' branch
$newFeature = 'feature/f3-merge-conflict'
Invoke-GitCommand "switch --create $newFeature $previousFeature"
Invoke-GitCommand "push -u origin $newFeature"
Step-ByStep

# Create PR for 'feature/f3-merge-conflict' into the 'develop' branch and wait for user to complete.
Open-GithubPullRequest -Source $newFeature -Target 'develop'

# Pull latest changes into the 'feature/f3-merge-conflict' branch
Invoke-GitCommand "pull"

# Pull latest changes into 'develop' branch
Invoke-GitCommand "switch develop"
Invoke-GitCommand "pull"

# Pull latest changes into 'feature/f3' branch
Invoke-GitCommand "switch $previousFeature"
Invoke-GitCommand "pull"
Step-ByStep

# Delete the 'feature/f3-merge-conflict' branch from 'origin' and local repos.
Invoke-GitCommand "push --delete origin $newFeature"
Invoke-GitCommand "branch --delete $newFeature"



# Create 'release/r3' branch from the 'main' branch
$newRelease = 'release/r3'
Invoke-GitCommand "switch --create $newRelease main"

# Merge 'feature/f3' branch into 'release/r3' branch, update 'README.md' file, commit changes, add tag, and push to 'origin'
Invoke-GitCommand "merge $previousFeature"
Add-Content -Path $readme -Value (Add-TimeStamp -Value "`n## $newRelease {0}")
Invoke-GitCommand "add -A"
Invoke-GitCommand "commit -m `"Add $newRelease`""
Invoke-GitCommand "tag -a $($newRelease.split('/')[1]) -m `"$newRelease`""
Invoke-GitCommand "push --tags -u origin $newRelease"
Step-ByStep

# Create PR for 'release/r3' branch into the 'main' branch and wait for user to complete.
Open-GithubPullRequest -Source $newRelease -Target 'main'

# Pull latest changes into 'main' branch
Invoke-GitCommand "switch main"
Invoke-GitCommand "pull"



Write-Host "`nDone`n" -ForegroundColor Green
