# Bridge-In Approval Flow - Godot Implementation Handoff

## Overview

For security, users must approve the Ashbane platform to transfer their NFTs before they can bridge items into the game. This is a standard ERC-721 `setApprovalForAll` operation that only needs to be done **once per wallet**.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        BRIDGE-IN FLOW                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. User opens Lockbox → sees items available to import                 │
│                                                                          │
│  2. User clicks "Import" on an item                                     │
│                                                                          │
│  3. Godot checks: GET /api/wallet/bridge-in/approval-status             │
│     ├─ If approved: true → Proceed to step 6                            │
│     └─ If approved: false → Continue to step 4                          │
│                                                                          │
│  4. Show approval prompt:                                                │
│     "Ashbane needs permission to import your items.                     │
│      This is a one-time approval. No items will be transferred yet."   │
│                                                                          │
│  5. User clicks "Approve" → Sign transaction via WalletConnect          │
│     ├─ GET /api/wallet/bridge-in/approval-tx → Get tx data              │
│     ├─ Send tx to wallet for signing                                    │
│     ├─ Wait for tx confirmation                                         │
│     └─ POST /api/wallet/bridge-in/verify-approval → Confirm             │
│                                                                          │
│  6. POST /api/wallet/bridge-in → Execute transfer                       │
│     └─ Item appears in inventory                                        │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## API Endpoints

### 1. Check Approval Status

```
GET /api/wallet/bridge-in/approval-status
Authorization: Bearer {token}
```

**Response (not approved):**
```json
{
  "approved": false,
  "wallet_address": "0x7ab18cbbcbae810a320dd706e5d429b17d3f8ed9",
  "platform_wallet": "0x4C5ad061b13122B927BfB3729A5bbFcd7BfBC5A2",
  "contract_address": "0x...",
  "chain_id": 84532
}
```

**Response (approved):**
```json
{
  "approved": true,
  "wallet_address": "0x7ab18cbbcbae810a320dd706e5d429b17d3f8ed9",
  "platform_wallet": "0x4C5ad061b13122B927BfB3729A5bbFcd7BfBC5A2",
  "contract_address": "0x...",
  "chain_id": 84532
}
```

### 2. Get Approval Transaction Data

```
GET /api/wallet/bridge-in/approval-tx
Authorization: Bearer {token}
```

**Response (needs approval):**
```json
{
  "already_approved": false,
  "transaction": {
    "to": "0xContractAddress",
    "data": "0xa22cb4650000000000000000000000004c5ad061b13122b927bfb3729a5bbfcd7bfbc5a20000000000000000000000000000000000000000000000000000000000000001",
    "chainId": 84532,
    "value": "0x0",
    "gas": "0xea60"
  },
  "description": "Approve Ashbane to transfer your NFTs for bridge-in",
  "one_time": true
}
```

**Response (already approved):**
```json
{
  "already_approved": true,
  "message": "Platform already approved for bridge-in transfers"
}
```

### 3. Verify Approval

```
POST /api/wallet/bridge-in/verify-approval
Authorization: Bearer {token}
```

**Response:**
```json
{
  "approved": true,
  "wallet_address": "0x7ab18cbbcbae810a320dd706e5d429b17d3f8ed9"
}
```

### 4. Bridge-In (existing endpoint, now with approval check)

```
POST /api/wallet/bridge-in
Authorization: Bearer {token}
Content-Type: application/json

{
  "token_ids": [1, 2, 3]
}
```

**Response (success):**
```json
{
  "success": true,
  "bridged_in": [
    {"token_id": 1, "item_name": "Enchanted Sword", "status": "in_game"}
  ],
  "failed": []
}
```

**Response (not approved - 403):**
```json
{
  "detail": {
    "error": "Platform not approved for transfers",
    "message": "You must approve Ashbane to transfer your NFTs before bridging in...",
    "requires_approval": true
  }
}
```

---

## Godot Implementation Guide

### Step 1: Add Approval State Tracking

```gdscript
# In ForgeItemManager.gd or a new BridgeManager.gd

var _bridge_approved: bool = false
var _approval_check_pending: bool = false

signal bridge_approval_status_changed(approved: bool)
signal bridge_approval_required()
```

### Step 2: Check Approval on Lockbox Open

```gdscript
func check_bridge_approval(callback: Callable = Callable()) -> void:
    """Check if platform is approved for bridge-in transfers"""
    if not AshbaneAuth or not AshbaneAuth.is_logged_in():
        _bridge_approved = false
        if callback.is_valid():
            callback.call(false)
        return

    var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-in/approval-status"
    var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

    var request = HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_on_approval_status_response.bind(request, callback))

    var error = request.request(url, headers, HTTPClient.METHOD_GET)
    if error != OK:
        request.queue_free()
        if callback.is_valid():
            callback.call(false)

func _on_approval_status_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
    request.queue_free()

    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        _bridge_approved = false
        if callback.is_valid():
            callback.call(false)
        return

    var json = JSON.new()
    if json.parse(body.get_string_from_utf8()) != OK:
        if callback.is_valid():
            callback.call(false)
        return

    var data = json.data
    _bridge_approved = data.get("approved", false)

    bridge_approval_status_changed.emit(_bridge_approved)

    if callback.is_valid():
        callback.call(_bridge_approved)
```

### Step 3: Get Approval Transaction Data

```gdscript
func get_approval_transaction(callback: Callable) -> void:
    """Get the approval transaction data for wallet signing"""
    var url = AshbaneAuth.get_api_base() + "/api/wallet/bridge-in/approval-tx"
    var headers = ["Authorization: Bearer " + AshbaneAuth.auth_token]

    var request = HTTPRequest.new()
    add_child(request)
    request.request_completed.connect(_on_approval_tx_response.bind(request, callback))

    request.request(url, headers, HTTPClient.METHOD_GET)

func _on_approval_tx_response(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, request: HTTPRequest, callback: Callable) -> void:
    request.queue_free()

    if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
        callback.call(null, "Failed to get approval transaction")
        return

    var json = JSON.new()
    if json.parse(body.get_string_from_utf8()) != OK:
        callback.call(null, "Invalid response")
        return

    var data = json.data

    if data.get("already_approved", false):
        _bridge_approved = true
        callback.call(null, "already_approved")
        return

    # Return the transaction data for WalletConnect
    callback.call(data.get("transaction"), null)
```

### Step 4: Modify Bridge-In UI Flow

```gdscript
# In Armory.gd or wherever bridge-in is triggered

func _on_bridge_in_clicked(token_id: int, item_name: String) -> void:
    """Handle bridge-in button click"""

    # First check approval status
    ForgeItemManager.check_bridge_approval(_on_approval_checked.bind(token_id, item_name))

func _on_approval_checked(approved: bool, token_id: int, item_name: String) -> void:
    if approved:
        # Proceed with bridge-in
        _execute_bridge_in(token_id, item_name)
    else:
        # Show approval prompt
        _show_approval_prompt(token_id, item_name)

func _show_approval_prompt(token_id: int, item_name: String) -> void:
    """Show one-time approval dialog"""
    var dialog = AcceptDialog.new()
    dialog.title = "Approve Import"
    dialog.dialog_text = """Ashbane needs permission to import items from your wallet.

This is a ONE-TIME approval that allows the game to transfer your forged items.
No items will be transferred until you click Import.

You'll need to sign this transaction in your wallet."""

    dialog.ok_button_text = "Approve"
    dialog.add_cancel_button("Cancel")

    dialog.confirmed.connect(_on_approval_confirmed.bind(token_id, item_name, dialog))
    dialog.canceled.connect(dialog.queue_free)

    add_child(dialog)
    dialog.popup_centered()

func _on_approval_confirmed(token_id: int, item_name: String, dialog: AcceptDialog) -> void:
    dialog.queue_free()

    # Get approval transaction and send to wallet
    ForgeItemManager.get_approval_transaction(_on_approval_tx_ready.bind(token_id, item_name))

func _on_approval_tx_ready(tx_data: Dictionary, error: String, token_id: int, item_name: String) -> void:
    if error == "already_approved":
        # Race condition - already approved, proceed
        _execute_bridge_in(token_id, item_name)
        return

    if error or tx_data == null:
        _show_error("Failed to prepare approval: " + str(error))
        return

    # Send to WalletConnect for signing
    # This depends on your WalletConnect integration
    WalletConnect.send_transaction(tx_data, _on_approval_tx_sent.bind(token_id, item_name))

func _on_approval_tx_sent(success: bool, tx_hash: String, token_id: int, item_name: String) -> void:
    if not success:
        _show_error("Approval transaction failed or was rejected")
        return

    # Wait for confirmation, then verify
    _show_status("Waiting for approval confirmation...")

    # Poll for approval status (or wait for tx confirmation)
    await get_tree().create_timer(5.0).timeout  # Wait for block confirmation

    ForgeItemManager.verify_approval(_on_approval_verified.bind(token_id, item_name))

func _on_approval_verified(approved: bool, token_id: int, item_name: String) -> void:
    if approved:
        _show_status("Approved! Importing item...")
        _execute_bridge_in(token_id, item_name)
    else:
        _show_error("Approval not detected. Please try again.")

func _execute_bridge_in(token_id: int, item_name: String) -> void:
    """Actually perform the bridge-in transfer"""
    ForgeItemManager.bridge_in([token_id], _on_bridge_in_complete.bind(item_name))
```

### Step 5: Handle 403 Error from Bridge-In

If you call bridge-in without approval, the API returns a 403. Handle this gracefully:

```gdscript
func _on_bridge_in_response(result: int, response_code: int, ...) -> void:
    # ...existing code...

    if response_code == 403:
        var json = JSON.new()
        json.parse(body.get_string_from_utf8())
        var detail = json.data.get("detail", {})

        if detail.get("requires_approval", false):
            # Trigger approval flow
            bridge_approval_required.emit()
            return

    # ...rest of handling...
```

---

## UI/UX Recommendations

### Approval Prompt Text

**Title:** "Approve Item Import"

**Body:**
```
Ashbane needs permission to import items from your wallet.

This is a ONE-TIME approval - you won't need to do this again.
No items will be transferred until you explicitly import them.

[Approve] [Cancel]
```

### Status Messages

- **Checking approval:** "Checking wallet permissions..."
- **Waiting for signature:** "Please sign the transaction in your wallet..."
- **Waiting for confirmation:** "Confirming approval on blockchain..."
- **Approval successful:** "Approved! You can now import items."
- **Approval failed:** "Approval failed. Please try again."

### Visual Indicators

Consider adding a badge or indicator showing approval status:
- **Not approved:** Orange warning icon next to "Import" buttons
- **Approved:** Green checkmark or no indicator needed

---

## Testing Checklist

- [ ] First-time user sees approval prompt before first bridge-in
- [ ] Approval transaction is correctly formatted for WalletConnect
- [ ] User can reject approval and return to lockbox
- [ ] After approval, bridge-in works without prompt
- [ ] Approval persists across sessions (it's on-chain)
- [ ] 403 error from bridge-in triggers approval flow
- [ ] UI handles network errors gracefully

---

## Contract Details

- **Contract:** AshbaneAchievements (ERC-721)
- **Chain:** Base Sepolia (chainId: 84532) / Base Mainnet (chainId: 8453)
- **Platform Wallet:** `0x4C5ad061b13122B927BfB3729A5bbFcd7BfBC5A2`
- **Approval Function:** `setApprovalForAll(operator, approved)`
- **Gas Estimate:** ~46,000 gas

---

## Security Notes

1. **One-time approval** - Users only need to approve once per wallet
2. **No token transfer on approval** - Approval only grants permission, doesn't move any NFTs
3. **Revocable** - Users can revoke approval anytime via the contract
4. **Standard ERC-721** - This is the standard NFT approval mechanism used by OpenSea, etc.
