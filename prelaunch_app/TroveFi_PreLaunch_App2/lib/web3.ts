import { createConfig, http } from 'wagmi'
import { flowMainnet, flowTestnet } from 'wagmi/chains'
import { walletConnect } from 'wagmi/connectors'

export const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'demo-project-id'

export const config = createConfig({
  chains: [flowMainnet, flowTestnet],
  connectors: [
    walletConnect({ projectId })
  ],
  transports: {
    [flowMainnet.id]: http(),
    [flowTestnet.id]: http(),
  },
})