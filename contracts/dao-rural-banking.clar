;; DAO for Rural Cooperative Banking with Savings Management
;; A comprehensive smart contract for rural financial inclusion

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

;; ===========================================
;; ERROR CONSTANTS
;; ===========================================

;; Core DAO errors
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-PROPOSAL-EXPIRED (err u105))
(define-constant ERR-MIN-STAKE-REQUIRED (err u106))
(define-constant ERR-LOAN-ACTIVE (err u107))

;; Savings system errors
(define-constant ERR-SAVINGS-ACCOUNT-EXISTS (err u200))
(define-constant ERR-SAVINGS-ACCOUNT-NOT-FOUND (err u201))
(define-constant ERR-INSUFFICIENT-SAVINGS-BALANCE (err u202))
(define-constant ERR-INVALID-SAVINGS-GOAL (err u203))
(define-constant ERR-MINIMUM-DEPOSIT-NOT-MET (err u205))
(define-constant ERR-WITHDRAWAL-LOCKED (err u206))
(define-constant ERR-INTEREST-CALCULATION-FAILED (err u207))

;; ===========================================
;; DATA VARIABLES
;; ===========================================

;; Core DAO configuration
(define-data-var minimum-stake uint u1000)
(define-data-var proposal-duration uint u144)
(define-data-var total-staked uint u0)
(define-data-var base-interest-rate uint u500)
(define-data-var max-interest-rate uint u2000)
(define-data-var reputation-threshold uint u10)

;; Savings system configuration
(define-data-var savings-interest-rate uint u300)  ;; 3% annual interest
(define-data-var minimum-savings-deposit uint u100)
(define-data-var goal-bonus-rate uint u50)         ;; 0.5% bonus for achieving goals

;; ===========================================
;; DATA MAPS
;; ===========================================

;; Core DAO member data
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

;; Loan proposals
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

;; Voting records
(define-map votes
    {
        proposal-id: uint,
        voter: principal,
    }
    bool
)

;; Savings accounts data structure
(define-map savings-accounts
    principal
    {
        balance: uint,
        last-deposit-timestamp: uint,
        total-deposits: uint,
        total-withdrawals: uint,
        interest-earned: uint,
        last-interest-calculation: uint,
        account-status: (string-ascii 20),
        lock-until-block: uint,
    }
)

;; Savings goals data structure
(define-map savings-goals
    principal
    {
        target-amount: uint,
        current-progress: uint,
        goal-description: (string-ascii 256),
        target-date: uint,
        goal-status: (string-ascii 20),
        reward-earned: uint,
    }
)

;; Auto-savings settings
(define-map auto-savings-settings
    principal
    {
        auto-amount: uint,
        frequency-blocks: uint,
        last-auto-save: uint,
        is-active: bool,
    }
)

;; Proposal counter
(define-data-var proposal-count uint u0)

;; ===========================================
;; CORE DAO FUNCTIONS
;; ===========================================

;; Calculate interest rate based on reputation and stake
(define-read-only (calculate-interest-rate (borrower principal))
    (let (
            (member-data (default-to {
                staked-amount: u0,
                last-stake-timestamp: u0,
                reputation-score: u0,
                active-loan: u0,
                total-repaid: u0,
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

;; Stake tokens to become a member
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

;; Create loan proposal
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
            (annual-blocks u52560)
            (total-interest (/ (* amount interest-rate repayment-period) (* annual-blocks u10000)))
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

;; Vote on proposal
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

;; ===========================================
;; SAVINGS ACCOUNT MANAGEMENT SYSTEM
;; ===========================================

;; Create a new savings account
(define-public (create-savings-account)
    (let (
            (existing-account (map-get? savings-accounts tx-sender))
        )
        (asserts! (is-none existing-account) ERR-SAVINGS-ACCOUNT-EXISTS)
        (map-set savings-accounts tx-sender {
            balance: u0,
            last-deposit-timestamp: burn-block-height,
            total-deposits: u0,
            total-withdrawals: u0,
            interest-earned: u0,
            last-interest-calculation: burn-block-height,
            account-status: "active",
            lock-until-block: u0,
        })
        (ok true)
    )
)

;; Deposit funds into savings account
(define-public (savings-deposit
        (token <ft-trait>)
        (amount uint)
    )
    (let (
            (account-data (unwrap! (map-get? savings-accounts tx-sender) ERR-SAVINGS-ACCOUNT-NOT-FOUND))
            (current-balance (unwrap! (contract-call? token get-balance tx-sender) ERR-INSUFFICIENT-BALANCE))
        )
        (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (>= amount (var-get minimum-savings-deposit)) ERR-MINIMUM-DEPOSIT-NOT-MET)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender) none))
        (map-set savings-accounts tx-sender
            (merge account-data {
                balance: (+ (get balance account-data) amount),
                last-deposit-timestamp: burn-block-height,
                total-deposits: (+ (get total-deposits account-data) amount),
            })
        )
        (ok true)
    )
)

;; Withdraw funds from savings account
(define-public (savings-withdraw
        (token <ft-trait>)
        (amount uint)
    )
    (let (
            (account-data (unwrap! (map-get? savings-accounts tx-sender) ERR-SAVINGS-ACCOUNT-NOT-FOUND))
        )
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (< burn-block-height (get lock-until-block account-data)) ERR-WITHDRAWAL-LOCKED)
        (asserts! (>= (get balance account-data) amount) ERR-INSUFFICIENT-SAVINGS-BALANCE)
        (try! (as-contract (contract-call? token transfer amount tx-sender tx-sender none)))
        (map-set savings-accounts tx-sender
            (merge account-data {
                balance: (- (get balance account-data) amount),
                total-withdrawals: (+ (get total-withdrawals account-data) amount),
            })
        )
        (ok true)
    )
)

;; Set or update savings goal
(define-public (set-savings-goal
        (target-amount uint)
        (description (string-ascii 256))
        (target-date uint)
    )
    (let (
            (account-data (unwrap! (map-get? savings-accounts tx-sender) ERR-SAVINGS-ACCOUNT-NOT-FOUND))
        )
        (asserts! (> target-amount u0) ERR-INVALID-SAVINGS-GOAL)
        (asserts! (> target-date burn-block-height) ERR-INVALID-SAVINGS-GOAL)
        
        (map-set savings-goals tx-sender {
            target-amount: target-amount,
            current-progress: (get balance account-data),
            goal-description: description,
            target-date: target-date,
            goal-status: "active",
            reward-earned: u0,
        })
        (ok true)
    )
)

;; Setup auto-savings
(define-public (setup-auto-savings
        (auto-amount uint)
        (frequency-blocks uint)
    )
    (let (
            (account-data (unwrap! (map-get? savings-accounts tx-sender) ERR-SAVINGS-ACCOUNT-NOT-FOUND))
        )
        (asserts! (> auto-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> frequency-blocks u0) ERR-INVALID-AMOUNT)
        
        (map-set auto-savings-settings tx-sender {
            auto-amount: auto-amount,
            frequency-blocks: frequency-blocks,
            last-auto-save: burn-block-height,
            is-active: true,
        })
        (ok true)
    )
)

;; Lock savings account for a period (useful for commitment savings)
(define-public (lock-savings-account (lock-blocks uint))
    (let (
            (account-data (unwrap! (map-get? savings-accounts tx-sender) ERR-SAVINGS-ACCOUNT-NOT-FOUND))
        )
        (map-set savings-accounts tx-sender
            (merge account-data {
                lock-until-block: (+ burn-block-height lock-blocks),
            })
        )
        (ok true)
    )
)

;; ===========================================
;; READ-ONLY FUNCTIONS
;; ===========================================

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
    (ok (unwrap! (map-get? proposals proposal-id) ERR-PROPOSAL-NOT-FOUND))
)

;; Get member data
(define-read-only (get-member-data (member principal))
    (ok (unwrap! (map-get? members member) ERR-NOT-AUTHORIZED))
)

;; Get savings account information
(define-read-only (get-savings-account (account-owner principal))
    (ok (map-get? savings-accounts account-owner))
)

;; Get savings goal information
(define-read-only (get-savings-goal (account-owner principal))
    (ok (map-get? savings-goals account-owner))
)

;; Get auto-savings settings
(define-read-only (get-auto-savings-settings (account-owner principal))
    (ok (map-get? auto-savings-settings account-owner))
)

;; Calculate potential interest for future periods
(define-read-only (calculate-potential-interest
        (account-owner principal)
        (blocks-ahead uint)
    )
    (let (
            (account-opt (map-get? savings-accounts account-owner))
        )
        (if (is-some account-opt)
            (let (
                    (account (unwrap-panic account-opt))
                    (annual-blocks u52560)
                    (interest-rate (var-get savings-interest-rate))
                    (potential-interest (/ (* (get balance account) interest-rate blocks-ahead) (* annual-blocks u10000)))
                )
                (ok potential-interest)
            )
            ERR-SAVINGS-ACCOUNT-NOT-FOUND
        )
    )
)

;; Get comprehensive savings summary
(define-read-only (get-savings-summary (account-owner principal))
    (let (
            (account-opt (map-get? savings-accounts account-owner))
        )
        (if (is-some account-opt)
            (let (
                    (account (unwrap-panic account-opt))
                    (goal-data (map-get? savings-goals account-owner))
                    (auto-settings (map-get? auto-savings-settings account-owner))
                )
                (ok {
                    account: account,
                    goal: goal-data,
                    auto-savings: auto-settings,
                    is-locked: (> (get lock-until-block account) burn-block-height),
                })
            )
            ERR-SAVINGS-ACCOUNT-NOT-FOUND
        )
    )
)