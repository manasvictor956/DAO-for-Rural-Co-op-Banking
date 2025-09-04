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
(define-constant ERR-INSUFFICIENT-CONTRIBUTIONS (err u109))
(define-constant ERR-WITHDRAWAL-LIMIT-EXCEEDED (err u110))
(define-constant ERR-CANNOT-DELEGATE-TO-SELF (err u111))
(define-constant ERR-DELEGATE-NOT-MEMBER (err u112))
(define-constant ERR-INTEREST-CALCULATION-FAILED (err u113))

(define-data-var minimum-stake uint u1000)
(define-data-var proposal-duration uint u144)
(define-data-var total-staked uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var base-interest-rate uint u500)
(define-data-var max-interest-rate uint u2000)
(define-data-var reputation-threshold uint u10)

(define-map members
    principal
    {
        staked-amount: uint,
        last-stake-timestamp: uint,
        reputation-score: uint,
        active-loan: uint,
        total-repaid: uint,
        contributions-balance: uint,
        total-contributions: uint,
        last-withdrawal-timestamp: uint,
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
        interest-rate: uint,
        total-interest-due: uint,
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

(define-map delegations
    principal
    principal
)

(define-data-var proposal-count uint u0)

(define-read-only (calculate-interest-rate (borrower principal))
    (let (
            (member-data (default-to {
                staked-amount: u0,
                last-stake-timestamp: u0,
                reputation-score: u0,
                active-loan: u0,
                total-repaid: u0,
                contributions-balance: u0,
                total-contributions: u0,
                last-withdrawal-timestamp: u0,
            }
                (map-get? members borrower)
            ))
            (reputation (get reputation-score member-data))
            (stake-ratio (if (> (var-get total-staked) u0)
                (/ (* (get staked-amount member-data) u10000)
                    (var-get total-staked)
                )
                u0
            ))
        )
        (ok (if (>= reputation (var-get reputation-threshold))
            (if (> stake-ratio u500)
                (var-get base-interest-rate)
                (+ (var-get base-interest-rate) u250)
            )
            (if (> stake-ratio u1000)
                (+ (var-get base-interest-rate) u500)
                (var-get max-interest-rate)
            )
        ))
    )
)

(define-read-only (calculate-interest-amount
        (principal-amount uint)
        (interest-rate uint)
        (duration-blocks uint)
    )
    (let (
            (annual-blocks u52560)
            (interest-per-block (/ interest-rate annual-blocks))
            (total-interest (/ (* principal-amount interest-per-block duration-blocks) u10000))
        )
        (ok total-interest)
    )
)

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
            contributions-balance: (default-to u0
                (get contributions-balance (map-get? members tx-sender))
            ),
            total-contributions: (default-to u0 (get total-contributions (map-get? members tx-sender))),
            last-withdrawal-timestamp: (default-to u0
                (get last-withdrawal-timestamp (map-get? members tx-sender))
            ),
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
            (interest-rate (unwrap! (calculate-interest-rate tx-sender)
                ERR-INTEREST-CALCULATION-FAILED
            ))
            (total-interest (unwrap!
                (calculate-interest-amount amount interest-rate repayment-period)
                ERR-INTEREST-CALCULATION-FAILED
            ))
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
            interest-rate: interest-rate,
            total-interest-due: total-interest,
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

(define-public (make-contribution
        (token <ft-trait>)
        (amount uint)
    )
    (let (
            (current-balance (unwrap! (contract-call? token get-balance tx-sender)
                ERR-INSUFFICIENT-BALANCE
            ))
            (member-data (default-to {
                staked-amount: u0,
                last-stake-timestamp: u0,
                reputation-score: u0,
                active-loan: u0,
                total-repaid: u0,
                contributions-balance: u0,
                total-contributions: u0,
                last-withdrawal-timestamp: u0,
            }
                (map-get? members tx-sender)
            ))
        )
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender)
            none
        ))
        (map-set members tx-sender
            (merge member-data {
                contributions-balance: (+ (get contributions-balance member-data) amount),
                total-contributions: (+ (get total-contributions member-data) amount),
                reputation-score: (+ (get reputation-score member-data) u1),
            })
        )
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok true)
    )
)

(define-public (withdraw-contribution
        (token <ft-trait>)
        (amount uint)
    )
    (let (
            (member-data (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
            (withdrawal-limit (/ (get contributions-balance member-data) u2))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (>= (get contributions-balance member-data) amount)
            ERR-INSUFFICIENT-CONTRIBUTIONS
        )
        (asserts! (<= amount withdrawal-limit) ERR-WITHDRAWAL-LIMIT-EXCEEDED)
        (try! (as-contract (contract-call? token transfer amount tx-sender tx-sender none)))
        (map-set members tx-sender
            (merge member-data {
                contributions-balance: (- (get contributions-balance member-data) amount),
                last-withdrawal-timestamp: burn-block-height,
            })
        )
        (var-set treasury-balance (- (var-get treasury-balance) amount))
        (ok true)
    )
)

(define-read-only (get-member-data (member principal))
    (ok (unwrap! (map-get? members member) ERR-NOT-AUTHORIZED))
)

(define-public (delegate-voting-power (delegate principal))
    (let (
            (delegator-data (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
            (delegate-data (unwrap! (map-get? members delegate) ERR-DELEGATE-NOT-MEMBER))
        )
        (asserts! (not (is-eq tx-sender delegate)) ERR-CANNOT-DELEGATE-TO-SELF)
        (map-set delegations tx-sender delegate)
        (ok true)
    )
)

(define-public (revoke-delegation)
    (let ((delegator-data (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED)))
        (map-delete delegations tx-sender)
        (ok true)
    )
)

(define-public (vote-as-delegate
        (proposal-id uint)
        (vote-bool bool)
        (delegator principal)
    )
    (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (delegate-data (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
            (delegator-data (unwrap! (map-get? members delegator) ERR-NOT-AUTHORIZED))
            (delegation (unwrap! (map-get? delegations delegator) ERR-NOT-AUTHORIZED))
        )
        (asserts! (is-eq tx-sender delegation) ERR-NOT-AUTHORIZED)
        (asserts!
            (not (default-to false
                (map-get? votes {
                    proposal-id: proposal-id,
                    voter: delegator,
                })
            ))
            ERR-ALREADY-VOTED
        )
        (asserts! (< burn-block-height (get end-burn-block-height proposal))
            ERR-PROPOSAL-EXPIRED
        )
        (map-set votes {
            proposal-id: proposal-id,
            voter: delegator,
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

(define-read-only (get-delegation (delegator principal))
    (ok (map-get? delegations delegator))
)

(define-public (repay-with-interest
        (token <ft-trait>)
        (proposal-id uint)
        (principal-amount uint)
        (interest-amount uint)
    )
    (let (
            (proposal (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
            (member-data (unwrap! (map-get? members tx-sender) ERR-NOT-AUTHORIZED))
            (total-payment (+ principal-amount interest-amount))
            (expected-interest (get total-interest-due proposal))
        )
        (asserts! (is-eq tx-sender (get proposer proposal)) ERR-NOT-AUTHORIZED)
        (asserts! (>= interest-amount expected-interest) ERR-INSUFFICIENT-BALANCE)
        (try! (contract-call? token transfer total-payment tx-sender
            (as-contract tx-sender) none
        ))
        (map-set loan-repayments { proposal-id: proposal-id }
            (+
                (default-to u0
                    (map-get? loan-repayments { proposal-id: proposal-id })
                )
                total-payment
            ))
        (map-set members tx-sender
            (merge member-data {
                total-repaid: (+ (get total-repaid member-data) total-payment),
                reputation-score: (+ (get reputation-score member-data) u2),
                active-loan: u0,
            })
        )
        (var-set treasury-balance (+ (var-get treasury-balance) interest-amount))
        (ok true)
    )
)

(define-read-only (get-loan-details (proposal-id uint))
    (match (map-get? proposals proposal-id)
        proposal (ok {
            loan-amount: (get loan-amount proposal),
            interest-rate: (get interest-rate proposal),
            total-interest-due: (get total-interest-due proposal),
            total-repayment-due: (+ (get loan-amount proposal) (get total-interest-due proposal)),
            repayment-deadline: (get repayment-deadline proposal),
        })
        ERR-PROPOSAL-NOT-FOUND
    )
)
