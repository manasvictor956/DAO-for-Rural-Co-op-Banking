(define-trait ft-trait (
    (transfer
        (uint principal principal (optional (buff 34)))
        (response bool uint)
    )
    (get-balance
        (principal)
        (response uint uint)
    )
))

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-PROPOSAL-EXPIRED (err u105))
(define-constant ERR-MIN-STAKE-REQUIRED (err u106))
(define-constant ERR-LOAN-ACTIVE (err u107))
(define-constant ERR-REPAYMENT-FAILED (err u108))

(define-data-var minimum-stake uint u1000)
(define-data-var proposal-duration uint u144)
(define-data-var total-staked uint u0)
(define-data-var treasury-balance uint u0)

(define-map members
    principal
    {
        staked-amount: uint,
        last-stake-timestamp: uint,
        reputation-score: uint,
        active-loan: uint,
        total-repaid: uint,
    }
)

(define-map proposals
    uint
    {
        proposer: principal,
        loan-amount: uint,
        description: (string-ascii 256),
        yes-votes: uint,
        no-votes: uint,
        status: (string-ascii 20),
        end-burn-block-height: uint,
        repayment-deadline: uint,
    }
)

(define-map votes
    {
        proposal-id: uint,
        voter: principal,
    }
    bool
)
(define-map loan-repayments
    { proposal-id: uint }
    uint
)

(define-data-var proposal-count uint u0)

(define-public (stake-tokens
        (token <ft-trait>)
        (amount uint)
    )
    (let ((current-balance (unwrap! (contract-call? token get-balance tx-sender)
            ERR-INSUFFICIENT-BALANCE
        )))
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender)
            none
        ))
        (map-set members tx-sender {
            staked-amount: (+ (default-to u0 (get staked-amount (map-get? members tx-sender)))
                amount
            ),
            last-stake-timestamp: burn-block-height,
            reputation-score: (default-to u0 (get reputation-score (map-get? members tx-sender))),
            active-loan: u0,
            total-repaid: (default-to u0 (get total-repaid (map-get? members tx-sender))),
        })
        (var-set total-staked (+ (var-get total-staked) amount))
        (ok true)
    )
)

(define-public (create-loan-proposal
        (amount uint)
        (description (string-ascii 256))
        (repayment-period uint)
    )
    (let (
            (member-data (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
            (proposal-id (+ (var-get proposal-count) u1))
        )
        (asserts! (>= (get staked-amount member-data) (var-get minimum-stake))
            ERR-MIN-STAKE-REQUIRED
        )
        (asserts! (is-eq (get active-loan member-data) u0) ERR-LOAN-ACTIVE)
        (map-set proposals proposal-id {
            proposer: tx-sender,
            loan-amount: amount,
            description: description,
            yes-votes: u0,
            no-votes: u0,
            status: "active",
            end-burn-block-height: (+ burn-block-height (var-get proposal-duration)),
            repayment-deadline: (+ burn-block-height repayment-period),
        })
        (var-set proposal-count proposal-id)
        (ok proposal-id)
    )
)

(define-public (vote
        (proposal-id uint)
        (vote-bool bool)
    )
    (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (member-data (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
        )
        (asserts!
            (not (default-to false
                (map-get? votes {
                    proposal-id: proposal-id,
                    voter: tx-sender,
                })
            ))
            ERR-ALREADY-VOTED
        )
        (asserts! (< burn-block-height (get end-burn-block-height proposal))
            ERR-PROPOSAL-EXPIRED
        )
        (map-set votes {
            proposal-id: proposal-id,
            voter: tx-sender,
        }
            vote-bool
        )
        (map-set proposals proposal-id
            (merge proposal {
                yes-votes: (if vote-bool
                    (+ (get yes-votes proposal) u1)
                    (get yes-votes proposal)
                ),
                no-votes: (if (not vote-bool)
                    (+ (get no-votes proposal) u1)
                    (get no-votes proposal)
                ),
            })
        )
        (ok true)
    )
)

(define-public (repay-loan
        (token <ft-trait>)
        (proposal-id uint)
        (amount uint)
    )
    (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (member-data (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
        )
        (asserts! (is-eq tx-sender (get proposer proposal)) ERR-NOT-AUTHORIZED)
        (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender)
            none
        ))
        (map-set loan-repayments { proposal-id: proposal-id }
            (+
                (default-to u0
                    (map-get? loan-repayments { proposal-id: proposal-id })
                )
                amount
            ))
        (map-set members tx-sender
            (merge member-data {
                total-repaid: (+ (get total-repaid member-data) amount),
                reputation-score: (+ (get reputation-score member-data) u1),
            })
        )
        (ok true)
    )
)

(define-read-only (get-proposal (proposal-id uint))
    (ok (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
)

(define-read-only (get-member-data (member principal))
    (ok (unwrap! (map-get? members member) ERR-NOT-AUTHORIZED))
)
