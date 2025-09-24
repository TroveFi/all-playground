#!/usr/bin/env python3
# discover_pair_address.py
from web3 import Web3

RPC = "https://mainnet.evm.nodes.onflow.org"
FACTORY_V2 = "0x29372c22459a4e373851798bFd6808e71EA34A71"   # KittyPunch factory
WFLOW  = "0xd3bF53DAC106A0290B0483EcBC89d40FcC961f3e"
ANKRFLOW = "0x1b97100eA1D7126C4d60027e231EA4CB25314bdb"

FACTORY_ABI=[{"constant":True,"inputs":[{"name":"tokenA","type":"address"},{"name":"tokenB","type":"address"}],
"name":"getPair","outputs":[{"name":"pair","type":"address"}],"type":"function"}]

def main():
    w3 = Web3(Web3.HTTPProvider(RPC, request_kwargs={'timeout':30}))
    if not w3.is_connected():
        raise SystemExit("RPC not connected")
    f = w3.eth.contract(address=Web3.to_checksum_address(FACTORY_V2), abi=FACTORY_ABI)
    pair = f.functions.getPair(Web3.to_checksum_address(WFLOW), Web3.to_checksum_address(ANKRFLOW)).call()
    if int(pair,16)==0:
        print("No pair found (WFLOW/ankrFLOW).")
    else:
        print("WFLOW/ankrFLOW LP address:", pair)
if __name__=="__main__":
    main()
