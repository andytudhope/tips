local json = require('json')

CRED = "Sa0iBLPNyJQrwpTTG-tWLQU-1QeUAJA73DdxGGiKoJc"

if not Balances then Balances = { [ao.id] = 0 } end

-- constant for minting curve
if not C then C = 10000000 end
-- It may seem strange to set the initial balance to 50000000
-- when there is no CRED actually in this process.
-- However, this cuts off the initial, 'unfair' part of the curve
-- where very few CRED mint lots of TIPS, and ensures a 'floor' price
-- without any tokens actually being possessed by anyone, hence there
-- can be no question about whether this is a ponzi scheme with a shadowy
-- beneficiary sitting on a pile of unearned tokens.
if not TotalCred then TotalCred = 50000000 end

if Name ~= 'tips' then Name = 'tips' end

if Ticker ~= 'TIPS' then Ticker = 'TIPS' end

if Denomination ~= 3 then Denomination = 3 end

if not Logo then Logo = 'OVJ2EyD3dKFctzANd0KX_PCgg8IQvk0zYqkWIj-aeaU' end

-- Accepting CRED, minting TIPS
local function calcTip(quantity)
  local ln = math.log((((TotalCred + quantity))) / TotalCred)
  local tipsToMint = C * ln
  TotalCred = TotalCred + quantity
  return tipsToMint
end

-- Burning TIPS, sending CRED
local function calcCred(quantity)
  local e = math.exp(quantity / C)
  local credToSend = TotalCred - (TotalCred / e)
  TotalCred = TotalCred - credToSend
  -- we have to return a rounded value here as CRED doesn't accept transfers of a string like "499.987"
  return math.floor(credToSend + 0.5)
end

-- Handler for incoming messages
Handlers.add('info', Handlers.utils.hasMatchingTag('Action', 'Info'), function(m)
    ao.send(
        { Target = m.From, Tags = { Name = Name, Ticker = Ticker, Logo = Logo, Denomination = tostring(Denomination) } })
    end)

-- Handlers for token balances and info
Handlers.add('balance', Handlers.utils.hasMatchingTag('Action', 'Balance'), function(m)
    local bal = '0'

    -- If not Target is provided, then return the Senders balance
    if (m.Tags.Target and Balances[m.Tags.Target]) then
        bal = tostring(Balances[m.Tags.Target])
    elseif Balances[m.From] then
        bal = tostring(Balances[m.From])
    end

    ao.send({
        Target = m.From,
        Tags = { Target = m.From, Balance = bal, Ticker = Ticker, Data = json.encode(tonumber(bal)) }
    })
    end)

-- Handler for all balances
Handlers.add('balances', Handlers.utils.hasMatchingTag('Action', 'Balances'),
    function(m) ao.send({ Target = m.From, Data = json.encode(Balances) }) end)

-- Handler for transfers
Handlers.add('transfer', Handlers.utils.hasMatchingTag('Action', 'Transfer'), function(m)
    assert(type(m.Tags.Recipient) == 'string', 'Recipient is required!')
    assert(type(m.Tags.Quantity) == 'string', 'Quantity is required!')

    if not Balances[m.From] then Balances[m.From] = 0 end

    if not Balances[m.Tags.Recipient] then Balances[m.Tags.Recipient] = 0 end
    local qty = tonumber(m.Tags.Quantity)
    assert(type(qty) == 'number', 'qty must be number')

    if Balances[m.From] >= qty then
      Balances[m.From] = Balances[m.From] - qty
      Balances[m.Tags.Recipient] = Balances[m.Tags.Recipient] + qty

      --[[
        Only Send the notifications to the Sender and Recipient
        if the Cast tag is not set on the Transfer message
      ]] --
      if not m.Tags.Cast then
        -- Send Debit-Notice to the Sender
        ao.send({
          Target = m.From,
          Tags = { Action = 'Debit-Notice', Recipient = m.Tags.Recipient, Quantity = tostring(qty) }
        })
        -- Send Credit-Notice to the Recipient
        ao.send({
          Target = m.Tags.Recipient,
          Tags = { Action = 'Credit-Notice', Sender = m.From, Quantity = tostring(qty) }
        })
      end
    else
      ao.send({
        Target = m.Tags.From,
        Tags = { Action = 'Transfer-Error', ['Message-Id'] = m.Id, Error = 'Insufficient Balance!' }
      })
    end
  end)

-- Handler for processes that want to buy TIPS
Handlers.add(
  "buy",
  function(m)
      return
          m.Tags.Action == "Credit-Notice" and
          m.From == CRED and
          m.Tags.Quantity >= "1000" and "continue" -- 1 CRED == 1000 CRED Units
  end,
  function(m)
      local qty = tonumber(m.Tags.Quantity)
      if qty >= 1 then
        local tips = calcTip(qty)
        Balances[m.Tags.Sender] = (Balances[m.Tags.Sender] or 0) + tips
        ao.send({Target = m.Tags.Sender, Data = "Your TIP balance is now: " .. Balances[m.Tags.Sender]})
      else
        ao.send({Target = m.Tags.Sender, Data = "You need to send at least 1000 CRED"})
      end
  end
)

-- Handler for processes that want to sell TIPS
Handlers.add(
  "sell",
  Handlers.utils.hasMatchingTag('Action', 'Sell'),
  function(m)
    assert(type(m.Tags.Quantity) == 'string', 'Quantity is required!')
    local qty = tonumber(m.Tags.Quantity)
    assert(type(qty) == 'number', 'qty must be number')

    if not Balances[m.From] then Balances[m.From] = 0 end
    if Balances[m.From] >= qty then
        if qty >= 1 then
          local cred = tostring(calcCred(qty))
          Balances[m.From] = Balances[m.From] - qty
          ao.send({Target = CRED, Action = 'Transfer', Recipient = m.From, Quantity = cred})
        else
          ao.send({Target = m.From, Data = 'Please sell at least 1 TIPS'})
        end
    else
        ao.send({Target = m.From, Data = 'Insufficient Balance'})
    end
  end
)