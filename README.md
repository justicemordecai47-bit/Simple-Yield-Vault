# 🏦 Simple Yield Vault MVP

Welcome to the **Simple Yield Vault**! This Clarity smart contract implements a yield-generating vault on the Stacks blockchain. Users can deposit STX, earn simulated yield through a rebase mechanism, and withdraw their funds with interest. 🚀

## ✨ Features

- **💸 Deposit STX**: Users can deposit STX into the vault and receive "shares" representing their ownership.
- **📈 Simulated Yield**: The contract owner can trigger a "rebase" to increase the global share value, simulating APY.
- **🔄 Withdraw Anytime**: Users can withdraw their principal + accrued interest by burning their shares.
- **🛡️ Secure Tracking**: Maintains user balances using a robust share-to-asset exchange rate model.
- **🚫 Pausable**: Admin can pause/unpause deposits and withdrawals for safety.

## 🛠 Usage Instructions

### 1. Initialize
The contract starts with a rebase index of `1.0`.

### 2. Deposit Funds
Call the `deposit` function with the amount of uSTX you wish to stake.
```clarity
(contract-call? .yield-vault deposit u1000000)
```

### 3. Simulating Yield (Admin Only)
The owner calls `rebase` with a basis point rate (e.g., `u100` = 1%) to increase the value of all shares.
```clarity
(contract-call? .yield-vault rebase u100)
```

### 4. Check Balance
Anyone can check the current STX value of their shares.
```clarity
(contract-call? .yield-vault get-user-balance 'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5)
```

### 5. Withdraw
Burn shares to receive STX back.
```clarity
(contract-call? .yield-vault withdraw u500) ;; Withers 500 shares
;; OR
(contract-call? .yield-vault withdraw-all)
```

