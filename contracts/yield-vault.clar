(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-INVALID-AMOUNT (err u1001))
(define-constant ERR-INSUFFICIENT-BALANCE (err u1002))
(define-constant ERR-PAUSED (err u1003))
(define-constant ERR-REBASE-TOO-HIGH (err u1004))
(define-constant ERR-ZERO-ADDRESS (err u1005))
(define-constant ERR-ALREADY-INITIALIZED (err u1006))
(define-constant ERR-MATH-OVERFLOW (err u1007))
(define-constant ERR-NO-YIELD-TO-HARVEST (err u1009))

(define-constant CONTRACT-OWNER tx-sender)
(define-constant SCALE-FACTOR u100000000)
(define-constant MAX-REBASE-RATE u5000) ;; 50% max at once

(define-data-var total-deposited uint u0)
(define-data-var total-shares uint u0)
(define-data-var rebase-index uint u100000000) ;; Starts 1.0 (with scale factor)
(define-data-var last-rebase-block uint u0)
(define-data-var is-paused bool false)
(define-data-var vault-name (string-ascii 32) "Simple Yield Vault")

(define-map UserShares
    principal
    uint
)
(define-map UserStats
    principal
    {
        total-deposited: uint,
        total-withdrawn: uint,
        last-action-block: uint,
    }
)

(define-public (pause)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (var-set is-paused true))
    )
)

(define-public (resume)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (var-set is-paused false))
    )
)

(define-public (update-vault-name (new-name (string-ascii 32)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (var-set vault-name new-name))
    )
)

(define-private (calculate-stx-value (shares uint))
    (let ((current-index (var-get rebase-index)))
        (/ (* shares current-index) SCALE-FACTOR)
    )
)

(define-private (calculate-shares (stx-amount uint))
    (let ((current-index (var-get rebase-index)))
        (if (is-eq current-index u0)
            stx-amount
            (/ (* stx-amount SCALE-FACTOR) current-index)
        )
    )
)

(define-read-only (get-total-stx-in-vault)
    (ok (stx-get-balance (as-contract tx-sender)))
)

(define-read-only (get-user-shares (user principal))
    (ok (default-to u0 (map-get? UserShares user)))
)

(define-read-only (get-user-balance (user principal))
    (let ((shares (default-to u0 (map-get? UserShares user))))
        (ok (calculate-stx-value shares))
    )
)

(define-read-only (get-current-index)
    (ok (var-get rebase-index))
)

(define-read-only (get-vault-status)
    (ok {
        paused: (var-get is-paused),
        total-shares: (var-get total-shares),
        total-deposited: (var-get total-deposited),
        current-index: (var-get rebase-index),
    })
)

(define-public (deposit (amount uint))
    (let (
            (sender tx-sender)
            (shares-to-mint (calculate-shares amount))
            (current-shares (default-to u0 (map-get? UserShares sender)))
            (stats (default-to {
                total-deposited: u0,
                total-withdrawn: u0,
                last-action-block: u0,
            }
                (map-get? UserStats sender)
            ))
        )
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)

        (try! (stx-transfer? amount sender (as-contract tx-sender)))

        (map-set UserShares sender (+ current-shares shares-to-mint))
        (map-set UserStats sender
            (merge stats {
                total-deposited: (+ (get total-deposited stats) amount),
                last-action-block: block-height,
            })
        )

        (var-set total-shares (+ (var-get total-shares) shares-to-mint))
        (var-set total-deposited (+ (var-get total-deposited) amount))

        (print {
            event: "deposit",
            user: sender,
            amount: amount,
            shares-minted: shares-to-mint,
            index: (var-get rebase-index),
        })
        (ok shares-to-mint)
    )
)

(define-public (withdraw (shares-to-burn uint))
    (let (
            (sender tx-sender)
            (current-shares (default-to u0 (map-get? UserShares sender)))
            (stx-amount (calculate-stx-value shares-to-burn))
            (stats (default-to {
                total-deposited: u0,
                total-withdrawn: u0,
                last-action-block: u0,
            }
                (map-get? UserStats sender)
            ))
        )
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (asserts! (> shares-to-burn u0) ERR-INVALID-AMOUNT)
        (asserts! (>= current-shares shares-to-burn) ERR-INSUFFICIENT-BALANCE)

        (try! (as-contract (stx-transfer? stx-amount tx-sender sender)))

        (map-set UserShares sender (- current-shares shares-to-burn))
        (map-set UserStats sender
            (merge stats {
                total-withdrawn: (+ (get total-withdrawn stats) stx-amount),
                last-action-block: block-height,
            })
        )

        (var-set total-shares (- (var-get total-shares) shares-to-burn))
        (var-set total-deposited (- (var-get total-deposited) stx-amount))

        (print {
            event: "withdraw",
            user: sender,
            stx-amount: stx-amount,
            shares-burned: shares-to-burn,
            index: (var-get rebase-index),
        })
        (ok stx-amount)
    )
)

(define-public (withdraw-all)
    (let (
            (sender tx-sender)
            (current-shares (default-to u0 (map-get? UserShares sender)))
        )
        (if (> current-shares u0)
            (withdraw current-shares)
            (ok u0)
        )
    )
)

(define-public (rebase (rate-bips uint))
    (let (
            (current-index (var-get rebase-index))
            (index-increase (/ (* current-index rate-bips) u10000)) ;; rate is basis points (1 = 0.01%)
            (new-index (+ current-index index-increase))
        )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (<= rate-bips MAX-REBASE-RATE) ERR-REBASE-TOO-HIGH)

        (var-set rebase-index new-index)
        (var-set last-rebase-block block-height)

        (print {
            event: "rebase",
            old-index: current-index,
            new-index: new-index,
            rate: rate-bips,
        })
        (ok new-index)
    )
)

(define-public (transfer
        (amount-shares uint)
        (recipient principal)
    )
    (let (
            (sender tx-sender)
            (sender-shares (default-to u0 (map-get? UserShares sender)))
            (recipient-shares (default-to u0 (map-get? UserShares recipient)))
        )
        (asserts! (not (var-get is-paused)) ERR-PAUSED)
        (asserts! (> amount-shares u0) ERR-INVALID-AMOUNT)
        (asserts! (not (is-eq sender recipient)) ERR-INVALID-AMOUNT)
        (asserts! (>= sender-shares amount-shares) ERR-INSUFFICIENT-BALANCE)

        (map-set UserShares sender (- sender-shares amount-shares))
        (map-set UserShares recipient (+ recipient-shares amount-shares))

        (print {
            event: "transfer",
            from: sender,
            to: recipient,
            shares: amount-shares,
        })
        (ok true)
    )
)

(define-public (donate-to-pool (amount uint))
    (let ((sender tx-sender))
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (try! (stx-transfer? amount sender (as-contract tx-sender)))
        (var-set total-deposited (+ (var-get total-deposited) amount))
        (print {
            event: "donation",
            user: sender,
            amount: amount,
        })

        (ok true)
    )
)

;; Flash Loan Feature
(define-constant FLASH-LOAN-FEE u5) ;; 0.05% fee
(define-constant ERR-LOAN-FAILED (err u1008))

(use-trait flash-loan-user .flash-loan-user-trait.flash-loan-user)

(define-public (flash-loan
        (amount uint)
        (recipient <flash-loan-user>)
    )
    (let (
            (sender tx-sender)
            (pre-balance (stx-get-balance (as-contract tx-sender)))
            (fee (/ (* amount FLASH-LOAN-FEE) u10000))
            (repay-amount (+ amount fee))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= pre-balance amount) ERR-INSUFFICIENT-BALANCE)

        ;; Transfer loan amount to recipient
        (try! (as-contract (stx-transfer? amount tx-sender (contract-of recipient))))

        ;; Execute the flash loan operation
        ;; The recipient contract must implement execute-operation
        (try! (contract-call? recipient execute-operation amount sender))

        ;; Verify repayment
        (let ((post-balance (stx-get-balance (as-contract tx-sender))))
            (asserts! (>= post-balance (+ pre-balance fee)) ERR-LOAN-FAILED)

            ;; Update total deposited to reflect the earned fee
            ;; This increases the value of each share
            (var-set total-deposited (+ (var-get total-deposited) fee))

            (print {
                event: "flash-loan",
                user: sender,
                recipient: (contract-of recipient),
                amount: amount,
                fee: fee,
            })
            (ok fee)
        )
    )
)

;; Permissionless Yield Harvesting
;; Allows anyone to trigger a rebase if the contract holds more STX than required
;; This effectively distributes yield from flash loan fees and donations to all share holders
(define-public (harvest)
    (let (
            (current-total-shares (var-get total-shares))
            (current-index (var-get rebase-index))
            (total-assets (stx-get-balance (as-contract tx-sender)))
            ;; Calculate how much STX is currently backed by shares
            ;; required-balance = (shares * index) / SCALE-FACTOR
            (required-balance (/ (* current-total-shares current-index) SCALE-FACTOR))
        )
        ;; Can only harvest if there are shares and we have excess assets
        (asserts! (> current-total-shares u0) ERR-INVALID-AMOUNT)
        (asserts! (> total-assets required-balance) ERR-NO-YIELD-TO-HARVEST)

        ;; Calculate new index based on actual assets
        ;; new-index = (total-assets * SCALE-FACTOR) / total-shares
        (let ((new-index (/ (* total-assets SCALE-FACTOR) current-total-shares)))
            ;; Update global index
            (var-set rebase-index new-index)
            (var-set last-rebase-block block-height)

            (print {
                event: "harvest",
                caller: tx-sender,
                old-index: current-index,
                new-index: new-index,
                total-assets: total-assets,
            })
            (ok new-index)
        )
    )
)
