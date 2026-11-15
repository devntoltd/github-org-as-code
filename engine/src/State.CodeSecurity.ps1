# Code security reads: the two configurations the engine manages, the defaults and the configuration of each
# repository. Read-only.

function Find-CodeSecurityConfiguration {
    # The organization configuration of the exact name, $null when there is none, or a stop when the name is taken
    # otherwise. Names are unique across the organization whatever their case, so creating the configuration would
    # fail with a less helpful message, and an update never renames one.
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Configurations,
        [Parameter(Mandatory)][string]$Name,
        # The config field of the name, such as codeSecurity.public.name.
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Organization
    )

    $match = $Configurations | Where-Object { $_.target_type -eq 'organization' -and [string]$_.name -ceq $Name } | Select-Object -First 1
    $taken = $Configurations | Where-Object { [string]$_.name -eq $Name } | Select-Object -First 1
    if (-not $match -and $taken) {
        switch ([string]$taken.target_type) {
            'organization' {
                throw "The code security configuration '$($taken.name)' of '$Organization' differs from $Path '$Name' only in case; use the same spelling in the config, or rename the configuration at https://github.com/organizations/$Organization/settings/security_products."
            }
            'global' { throw "'$Name' is the name of a built-in GitHub code security configuration; choose another $Path." }
            'enterprise' { throw "'$Name' is the name of an enterprise code security configuration; choose another $Path." }
            default { throw "'$Name' is the name of a code security configuration of type '$($taken.target_type)'; choose another $Path." }
        }
    }
    return $match
}

function Read-CodeSecurityState {
    # The configurations named in the config (organization configurations only, the exact names), which
    # configurations are defaults for new repositories, and the configuration of every repository.
    param(
        [Parameter(Mandatory)][string]$Organization,
        # Key of $script:CodeSecurityVisibilities (private, public) -> the configuration name of that section.
        [Parameter(Mandatory)][System.Collections.IDictionary]$Names,
        # From Read-OrgRepository.
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$OrgRepository
    )

    Write-StateProgress -Status 'code security configurations'
    $configurations = @(Read-OrgEndpoint -Endpoint "orgs/$Organization/code-security/configurations?per_page=100" -Paginate)
    $own = [ordered]@{}
    foreach ($key in $script:CodeSecurityVisibilities.Keys) {
        $match = Find-CodeSecurityConfiguration -Configurations $configurations -Name ([string]$Names[$key]) -Path "codeSecurity.$key.name" -Organization $Organization
        $configuration = $null
        if ($match) {
            $configuration = [pscustomobject]@{
                Id          = [long]$match.id
                Name        = [string]$match.name
                Description = [string]$match.description
                Enforcement = [string]$match.enforcement
                Settings    = ConvertTo-FieldMap -Response $match -Section "codeSecurity.$key.settings"
            }
        }
        $own[$key] = [pscustomobject]@{ Configuration = $configuration; Default = $null }
    }

    Write-StateProgress -Status 'code security defaults'
    $otherDefaults = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/code-security/configurations/defaults")) {
        $owner = $own.Values | Where-Object { $_.Configuration -and [long]$entry.configuration.id -eq $_.Configuration.Id } | Select-Object -First 1
        if ($owner) {
            $owner.Default = [string]$entry.default_for_new_repos
        }
        else {
            $otherDefaults.Add([pscustomobject]@{ Name = [string]$entry.configuration.name; DefaultForNewRepos = [string]$entry.default_for_new_repos })
        }
    }

    # Archived repositories are read-only, so attaching a configuration to them could never succeed and the attach
    # would be planned on every run.
    $active = @($OrgRepository | Where-Object { -not $_.Archived })
    # A handful of list reads instead of one read per repository. The list is documented for organization
    # configurations; it also answers for the built-in GitHub ones (checked 2026-10-04). A repository of an
    # enterprise configuration (not checked), and one a list shows as detached, is read on its own below.
    $listed = @{}
    foreach ($candidate in @($configurations | Where-Object { $_.target_type -in 'organization', 'global' })) {
        Write-StateProgress -Status "repositories of code security configuration '$($candidate.name)'"
        foreach ($item in @(Read-OrgEndpoint -Endpoint "orgs/$Organization/code-security/configurations/$($candidate.id)/repositories?per_page=100" -Paginate)) {
            if ([string]$item.status -ne 'detached') {
                $listed[[string]$item.repository.name] = [pscustomobject]@{ status = $item.status; configuration = $candidate }
            }
        }
    }

    $repositories = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $active) {
        $repository = $item.Name
        $attached = $listed[$repository]
        if (-not $attached) {
            Write-StateProgress -Status "code security configuration of repository '$repository'"
            $endpoint = "repos/$Organization/$repository/code-security-configuration"
            try {
                # 204 No Content (no configuration) reaches us as $null.
                $attached = Read-OrgEndpoint -Endpoint $endpoint
            }
            catch {
                # Deleted, renamed or transferred since the repository list was read; the warnings report it.
                if (-not (Test-GhStatus -ErrorRecord $_ -StatusCode 404)) {
                    throw
                }
                $skipped.Add($repository)
                continue
            }
        }
        $entry = [pscustomobject]@{ Id = $item.Id; Name = $repository; Visibility = $item.Visibility; ConfigurationId = $null; ConfigurationName = $null; Status = $null }
        if ($attached) {
            $entry.ConfigurationId = [long]$attached.configuration.id
            $entry.ConfigurationName = [string]$attached.configuration.name
            $entry.Status = [string]$attached.status
        }
        $repositories.Add($entry)
    }

    return [pscustomobject]@{
        Private             = $own.private
        Public              = $own.public
        OtherDefaults       = $otherDefaults.ToArray()
        Repositories        = $repositories.ToArray()
        SkippedRepositories = $skipped.ToArray()
    }
}
