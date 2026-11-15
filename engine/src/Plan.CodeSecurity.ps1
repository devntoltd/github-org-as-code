# Code security actions and warnings: an object with a lifecycle (create, update, default, attach). Pure: no GitHub calls.

# Statuses of a repository's code security configuration that need nothing: in effect, or on its way
# (https://docs.github.com/en/code-security/reference/security-at-scale/configuration-statuses). Any other status is a
# warning, a status GitHub adds later included; 'failed' has its own.
$script:CodeSecurityStatusesInEffect = @('attached', 'attaching', 'updating', 'enforced', 'enterprise_enforced')
$script:CodeSecurityStatusMeanings = @{
    removed               = 'a repository admin changed a setting it controls'
    removed_by_enterprise = 'an enterprise configuration conflicts with it'
    detached              = 'the repository is detached from it'
}

function Test-DefaultOverlap {
    # Whether two default_for_new_repos values cover some of the same repositories.
    param([string]$First, [string]$Second)

    if ('none' -in @($First, $Second) -or -not $First -or -not $Second) {
        return $false
    }
    return ($First -eq 'all') -or ($Second -eq 'all') -or ($First -eq $Second)
}

function Get-CodeSecurityAction {
    # The actions of the two configurations, private first.
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Current
    )

    foreach ($key in $script:CodeSecurityVisibilities.Keys) {
        Get-CodeSecurityConfigurationAction -Config $Config -Current $Current -Key $key
    }
}

function Get-CodeSecurityConfigurationAction {
    # Create or update the configuration of one visibility, make it the default of that visibility, attach it to the
    # repositories of that visibility without a configuration (by id: a scope would attach it to the others too, or
    # switch repositories that have one).
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Current,
        # A key of $script:CodeSecurityVisibilities.
        [Parameter(Mandatory)][string]$Key
    )

    $visibility = $script:CodeSecurityVisibilities[$Key]
    $section = $Config.codeSecurity.$Key
    $own = $Current.$Key
    $name = [string]$section.name
    $base = "orgs/$($Config.organization)/code-security/configurations"
    $desired = Get-ConfiguredValue -Config $Config -Section "codeSecurity.$Key.settings"

    if ($null -eq $own.Configuration) {
        # The id is known only after the create call; Invoke-GitHubOrgPlan replaces the token.
        $path = "$base/{configuration_id}"
        $enforcement = [string]$section.enforcement
        $body = [ordered]@{ name = $name; enforcement = $enforcement; description = [string]$section.description }
        foreach ($field in $desired.Keys) {
            $body[$field] = $desired[$field]
        }
        $summary = "+ create code security configuration '$name' ($enforcement): " + (@($desired.Keys | ForEach-Object { "${_}: $($desired[$_])" }) -join ', ')
        [pscustomobject]@{
            Action   = 'CreateCodeSecurityConfiguration'
            Target   = $name
            Method   = 'POST'
            Endpoint = $base
            Body     = $body
            Summary  = $summary
        }
    }
    else {
        $path = "$base/$($own.Configuration.Id)"
        $changed = [ordered]@{}
        $changes = [System.Collections.Generic.List[string]]::new()
        if ([string]$section.description -cne $own.Configuration.Description) {
            $changed.description = [string]$section.description
            $changes.Add("description: '$($own.Configuration.Description)' -> '$($section.description)'")
        }
        if ([string]$section.enforcement -cne $own.Configuration.Enforcement) {
            $changed.enforcement = [string]$section.enforcement
            $changes.Add("enforcement: $(Format-SettingValue $own.Configuration.Enforcement) -> $($section.enforcement)")
        }
        foreach ($field in $desired.Keys) {
            $currentValue = $own.Configuration.Settings[$field]
            if ($currentValue -cne $desired[$field]) {
                $changed[$field] = $desired[$field]
                $changes.Add("${field}: $(Format-SettingValue $currentValue) -> $($desired[$field])")
            }
        }
        if ($changed.Count -gt 0) {
            [pscustomobject]@{
                Action   = 'UpdateCodeSecurityConfiguration'
                Target   = $name
                Method   = 'PATCH'
                Endpoint = $path
                Body     = $changed
                Summary  = "~ update code security configuration '$name': $($changes -join '; ')"
            }
        }
    }

    $wanted = $visibility.Default
    # Not being a default is the same as 'none'.
    $currentDefault = if ($own.Default) { [string]$own.Default } else { 'none' }
    if ($wanted -cne $currentDefault) {
        $replaced = @($Current.OtherDefaults | Where-Object { Test-DefaultOverlap -First $wanted -Second $_.DefaultForNewRepos } |
                ForEach-Object { "'$($_.Name)' ($($_.DefaultForNewRepos))" })
        $summary = "~ make code security configuration '$name' the default for new repositories: $(Format-SettingValue $own.Default) -> $wanted"
        if ($replaced.Count -gt 0) {
            $summary += "; replaces $($replaced -join ', ')"
        }
        [pscustomobject]@{
            Action   = 'SetCodeSecurityDefault'
            Target   = $name
            Method   = 'PUT'
            Endpoint = "$path/defaults"
            Body     = [ordered]@{ default_for_new_repos = $wanted }
            Summary  = $summary
        }
    }

    # GitHub rejects 'selected' without ids, so a visibility without such repositories plans no attach.
    $unattached = @($Current.Repositories | Where-Object { $null -eq $_.ConfigurationId -and (Get-CodeSecurityVisibilityKey -Visibility $_.Visibility) -eq $Key })
    if ($unattached.Count -gt 0) {
        [pscustomobject]@{
            Action   = 'AttachCodeSecurityConfiguration'
            Target   = $name
            Method   = 'POST'
            Endpoint = "$path/attach"
            Body     = [ordered]@{ scope = 'selected'; selected_repository_ids = [long[]]@($unattached | ForEach-Object { $_.Id }) }
            Summary  = "+ attach code security configuration '$name' to the $($visibility.Label) repositories without one: $(@($unattached.Name) -join ', ')"
        }
    }
}

function Get-CodeSecurityVisibilityKey {
    # The key of $script:CodeSecurityVisibilities whose repositories have this visibility, private when GitHub names
    # one the engine does not know.
    param([AllowEmptyString()][string]$Visibility)

    foreach ($key in $script:CodeSecurityVisibilities.Keys) {
        if ($Visibility -in $script:CodeSecurityVisibilities[$key].Repositories) {
            return $key
        }
    }
    return 'private'
}

function Get-CodeSecurityWarning {
    # Repositories on another configuration than the one of their visibility, an attach that failed or no longer in
    # effect, and repositories whose configuration could not be read.
    param(
        [Parameter(Mandatory)][object]$Config,
        [AllowNull()][object]$CodeSecurity
    )

    $page = "https://github.com/organizations/$($Config.organization)/settings/security_products"
    # Key -> the id of that configuration, when it exists.
    $ownIds = @{}
    foreach ($key in $script:CodeSecurityVisibilities.Keys) {
        if ($CodeSecurity.$key.Configuration) {
            $ownIds[$key] = $CodeSecurity.$key.Configuration.Id
        }
    }
    foreach ($repository in @($CodeSecurity.Repositories)) {
        if ($null -eq $repository.ConfigurationId) {
            continue
        }
        $expected = Get-CodeSecurityVisibilityKey -Visibility $repository.Visibility
        $name = [string]$Config.codeSecurity.$expected.name
        $other = @($ownIds.Keys | Where-Object { $_ -ne $expected -and $ownIds[$_] -eq $repository.ConfigurationId })
        if ($other.Count -gt 0) {
            $otherLabel = $script:CodeSecurityVisibilities[$other[0]].Label
            "Repository '$($repository.Name)' is $($repository.Visibility) but uses code security configuration '$($repository.ConfigurationName)', which is for $otherLabel repositories, not '$name'. The engine leaves it alone; to switch it, open $page and apply '$name' to the repository."
            # It stays on that configuration, so its status is still worth knowing.
            $name = [string]$Config.codeSecurity.($other[0]).name
        }
        elseif ($repository.ConfigurationId -ne $ownIds[$expected]) {
            "Repository '$($repository.Name)' uses code security configuration '$($repository.ConfigurationName)', not '$name'. The engine leaves it alone; to switch it, open $page and apply '$name' to the repository."
            continue
        }
        if ($repository.Status -eq 'failed') {
            "Attaching code security configuration '$name' to repository '$($repository.Name)' failed. Open $page to see why, then re-run."
        }
        elseif ($repository.Status -cnotin $script:CodeSecurityStatusesInEffect) {
            $meaning = $script:CodeSecurityStatusMeanings[$repository.Status]
            if (-not $meaning) {
                $meaning = "GitHub reports the status $($repository.Status)"
            }
            # The configuration is still attached, so the attach of the plan (repositories without one) skips it.
            "Code security configuration '$name' is not in effect on repository '$($repository.Name)': $meaning ($($repository.Status)). The engine does not re-attach it; open $page and apply '$name' to the repository again."
        }
    }
    foreach ($repository in @($CodeSecurity.SkippedRepositories | Where-Object { $_ })) {
        "Repository '$repository' was listed, but its code security configuration could not be read: GitHub answered 404 (deleted, renamed or transferred during the run, or the gh account cannot see it). It is left out of this run; re-run to check it."
    }
}
