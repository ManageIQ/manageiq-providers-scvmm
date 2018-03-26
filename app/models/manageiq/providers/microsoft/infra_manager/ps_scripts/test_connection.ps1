import-module virtualmachinemanager

$hash = @{}

$ems = Get-SCVMMServer -ComputerName localhost |
  Select @{name='Guid';expression={$_.ManagedComputer.ID -As [string]}},
    @{name='Version';expression={$_.ServerInterfaceVersion -As [string]}}

$hash["ems"] = $ems

# Maximum depth is 4 due to VMHostNetworkAdapters
ConvertTo-Json -InputObject $hash -Depth 4 -Compress
