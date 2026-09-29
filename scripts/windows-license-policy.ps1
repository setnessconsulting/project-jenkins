function Test-Windows11ProLicense {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]] $Products = @()
    )

    foreach ($product in $Products) {
        if ($null -eq $product) {
            continue
        }

        if ($product.ApplicationID -ieq '55c92734-d682-4d71-983e-d6ec3f16059f' -and
            $product.LicenseStatus -eq 1 -and
            $product.LicenseFamily -ieq 'Professional' -and
            $product.Name -ieq 'Windows(R), Professional edition') {
            return $true
        }
    }

    return $false
}
