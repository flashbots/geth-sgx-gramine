const { ethers } = require("ethers");
const { FlashbotsBundleProvider, FlashbotsBundleResolution } = require("@flashbots/ethers-provider-bundle")

const TIMEOUT_MS = 5 * 60 * 1000;
const legacyGasPrice = ethers.BigNumber.from(10).pow(9).mul(120);
// Goerli settings
const CHAIN_ID = 5;
const MAIN_ADDRESS = "<address>"
const MAIN_PRIVATE_KEY = "<private-key>"


const CHAIN_URL = "https://0.0.0.0:8545"
const provider = new ethers.providers.JsonRpcProvider(CHAIN_URL, {
    chainId: CHAIN_ID
});
const mainWallet = new ethers.Wallet(MAIN_PRIVATE_KEY, provider);


async function main() {

    const flashbotsProvider = await FlashbotsBundleProvider.create(provider, mainWallet, CHAIN_URL);
    const mainNonce = await mainWallet.getTransactionCount();

    const legacyTransaction = {
	    to: MAIN_ADDRESS,
            value: ethers.BigNumber.from(legacyGasPrice).mul(100000),
	    gasPrice: legacyGasPrice,
	    gasLimit: 21000,
	    data: '0x',
	    nonce: mainNonce
	  }


    // Get block to target
    provider.on('block', async (blockNumber) => {
	        const block = await provider.getBlock(blockNumber)

        console.log(blockNumber);

        // Sign flashbot bundle
        const signedTransactions = await flashbotsProvider.signBundle([
            {
                signer: mainWallet,
                transaction: legacyTransaction
            }
        ]);
        const targetBlock = (await provider.getBlock(blockNumber)).number + 2;
        console.log('Got block number, trying to send bundle');

        // Submit bundle
        const bundleSubmission = await sendRawBundle(flashbotsProvider, signedTransactions, targetBlock)
        console.log('Bundle submitted, waiting')
        if ('error' in bundleSubmission) {
            throw new Error(bundleSubmission.error.message)
        }
        const waitResponse = await bundleSubmission.wait();
        console.log(`Wait Response: ${FlashbotsBundleResolution[waitResponse]}`);
        process.exit(0);
    });
}
async function sendRawBundle(flashbotsProvider, signedBundledTransactions, targetBlockNumber, opts) {
	const params = {
	    txs: signedBundledTransactions,
	    blockNumber: `0x${targetBlockNumber.toString(16)}`,
	    minTimestamp: opts === null || opts === void 0 ? void 0 : opts.minTimestamp,
	    maxTimestamp: opts === null || opts === void 0 ? void 0 : opts.maxTimestamp,
	    revertingTxHashes: opts === null || opts === void 0 ? void 0 : opts.revertingTxHashes
	};
	const request = JSON.stringify(flashbotsProvider.prepareRelayRequest('eth_sendBundle', [params]));
	const response = await flashbotsProvider.request(request);
	if (response.error !== undefined && response.error !== null) {
	    return {
		error: {
		    message: response.error.message,
		    code: response.error.code
		}
	    };
	}
	const bundleTransactions = signedBundledTransactions.map((signedTransaction) => {
	    const transactionDetails = ethers.utils.parseTransaction(signedTransaction);
	    return {
		signedTransaction,
		hash: ethers.utils.keccak256(signedTransaction),
		account: transactionDetails.from || '0x0',
		nonce: transactionDetails.nonce
	    };
	});
	return {
	    bundleTransactions,
	    wait: () => flashbotsProvider.waitForBlock(bundleTransactions, targetBlockNumber, TIMEOUT_MS),
	    simulate: () => flashbotsProvider.simulate(bundleTransactions.map((tx) => tx.signedTransaction), targetBlockNumber, undefined, opts === null || opts === void 0 ? void 0 : opts.minTimestamp),
	    receipts: () => flashbotsProvider.fetchReceipts(bundleTransactions),
	};
}
main()
