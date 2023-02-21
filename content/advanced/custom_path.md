---
title: Custom Derivation Path
weight: 7
---

## For Transparent Addresses Only

{{%notice note %}}
For a single account, it is easier to use the
scan sub account feature. 
{{%/notice %}}

If you have funds in a legacy wallet (pre NU-5)
that hasn't been upgraded to support transaction V5,
your funds are inaccessible.

However, you can create an account in YWallet using
the same seed phrase and derivation path.

The resulting secret key and address will be identical
and you will be able to sweep your funds.

## Ledger

For Ledger, the derivation path is `m/44'/133'/0'/0/0`
For a second account in Ledger, the path is `m/44'/133'/1'/0/0`,
and so on.

If you have made several transactions, Ledger will have
created additional addresses by incrementing the final number:
`m/44'/133'/0'/0/1`, etc.

{{%notice note %}}
The exact format of the path is important. 
`m/44'/133'/0'/0/1` is not the same as `m/44/133'/0'/0/1`
Note the absence of `'` on 44.
{{%/notice %}}

You can use the website [Mnemonic Code Converter](https://iancoleman.io/bip39/) to check your addresses. *Don't forget to switch the currency to ZEC*.

## Path

Given `account_index` and `address_index`,
the path is typically:

`m/44'/133'/account_index'/0/address_index`

for wallets that follow the BIP-44 spec.

## Private Key

Alternatively, you can input a private key that
follows the Bitcoin Wallet Import Format.

## How to

- Import an account using the seed phrase
- Switch to the account transparent address
- Long press on the QR code
- Enter the custom derivation path
- Check that the new transparent address matches what you expect

This feature is not compatible with the autoscan feature.

{{%img 2022-07-17_12-12-34.png %}}

## Sweep Funds

{{%img 2023-02-21_19-30-27.png %}}

If you have a private key from an external account with funds that you want to bring to 
YWallet, you can sweep them without having to modify your current account.

In fact, this is the recommended way for it leaves your account unchanged. The other methods
replace the transparent key derived from your seed phrase.

- Choose "Sweep" in the Advanced Menu. Turn on Advanced Mode if you haven't done it already.
- Enter the private key
- Select the destination pool
- Press OK

A transaction will be broadcast that transfers all the funds to the designated pool in your current account.
 
## Demo

{{%youtube LmIrVUA0tFM %}}

## Disclaimer

{{%notice warning %}}
Be advised that using your seed phrase online or in a hot
wallet compromises its security.
YWallet does not upload any data but your device may
be infected with malware that does. 
{{%/notice %}}

To mitigate the risks, sweep all the other funds from your hardware wallet to a new seed phrase and never use the old one.

<link href="/youtube.css" rel=stylesheet integrity>
<script src="/youtube.js"></script>
