import "@nomiclabs/hardhat-waffle"
import "@nomiclabs/hardhat-ethers"
import "hardhat-gas-reporter"
import "@nomiclabs/hardhat-etherscan"

import { bscTestPk, bscPk, bscscanApiKey } from './secrets.json';

export default {
    networks: {
        localhost: {
            url: "http://127.0.0.1:8545",
            accounts: [bscTestPk]
        },
        bscTestnet: {
            url: "https://data-seed-prebsc-2-s3.binance.org:8545/",
            chainId: 97,
            accounts: [bscTestPk],
        },
        bsc: {
            url: "https://bsc-dataseed.binance.org/",
            chainId: 56,
            accounts: [bscPk]
        },
        hardhat: {
            forking: {
              url: "https://bsc-dataseed3.binance.org/",
            }
        }
    },
    solidity: {
        compilers: [
            {
                version: "0.4.18",
                settings: {
                    optimizer: {
                        enabled: false
                    }
                }
            },
            {
                version: "0.5.16",
                settings: {
                    optimizer: {
                        enabled: true
                    }
                }
            },
            {
                version: "0.6.12",
                settings: {
                    optimizer: {
                        enabled: true
                    }
                }
            },
            {
                version: "0.7.0",
                settings: {
                    optimizer: {
                        enabled: true
                    }
                }
            }, 
            {
                version: "0.8.4",
                settings: {
                    optimizer: {
                        enabled: true
                    }
                }
            },
            {
                version: "0.8.7",
                settings: {
                    optimizer: {
                        enabled: true
                    }
                }
            },
        ]
    },
    etherscan: {
        apiKey: {
            bscTestnet: bscscanApiKey,
            bsc: bscscanApiKey
        }
    },
    paths: {
        sources: "./contracts",
        tests: "./test",
        cache: "./cache",
        artifacts: "./artifacts"
    },
    mocha: {
        timeout: 200000
    },
    gasReporter: {
        enabled: true,
        outputFile: './gas-report.txt',
        noColors: true,
        rst: true,
    }
}

