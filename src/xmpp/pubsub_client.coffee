xmpp = require('node-xmpp')
async = require('async')
NS = require('./ns')
errors = require('../errors')

class Request
    constructor: (conn, @opts, cb) ->
        @myJid = conn.jid
        iq = @requestIq().root()
        iq.attrs.to = @opts.jid
        conn.sendIq iq, (err, replyStanza) =>
            if err
                # wrap <error/> child
                cb(err or new errors.StanzaError(err))
            else
                result = null
                err = null
                try
                    result = @decodeReply replyStanza
                catch e
                    console.error e.stack
                    err = e
                cb err, result

    requestIq: ->
        throw new TypeError("Unimplemented request")

    decodeReply: (stanza) ->
        throw new TypeError("Unimplemented reply")

###
# XEP-0030: Service Discovery
###

class DiscoverRequest extends Request
    xmlns: undefined

    requestIq: ->
        console.log 'DiscoverRequest.requestIq': @opts
        queryAttrs =
            xmlns: @xmlns
        if @opts.node?
                queryAttrs.node = @opts.node
        new xmpp.Element('iq', type: 'get').
            c('query', queryAttrs)

    decodeReply: (stanza) ->
        @results = []
        queryEl = stanza?.getChild('query', @xmlns)
        if queryEl
            for child in queryEl.children
                unless typeof child is 'string'
                    @decodeReplyEl child
        @results

    # Can add to @results
    decodeReplyEl: (el) ->


class exports.DiscoverItems extends DiscoverRequest
    xmlns: NS.DISCO_ITEMS

    decodeReplyEl: (el) ->
        if el.is('item', @xmlns) and el.attrs.jid?
            result = { jid: el.attrs.jid }
            if el.attrs.node
                result.node = el.attrs.node
            @results.push result

class exports.DiscoverInfo extends DiscoverRequest
    xmlns: NS.DISCO_INFO

    decodeReplyEl: (el) ->
        @results.identities ?= []
        @results.features ?= []
        @results.forms ?= []
        switch el.getName()
            when "identity"
                @results.identities.push
                    name: el.attrs.name
                    category: el.attrs.category
                    type: el.attrs.type
            when "feature"
                @results.features.push el.attrs.var
            when "form"
                # TODO: .getForm(formType)
                @results.forms.push

##
# XEP-0060
##

class PubsubRequest extends Request
    xmlns: NS.PUBSUB
    requestIq: ->
        pubsubEl = new xmpp.Element('iq', type: @iqType()).
            c('pubsub', xmlns: @xmlns)
        pubsubEl.cnode(@pubsubChild().root())
        if @opts.actor
            pubsubEl.c('actor', xmlns: NS.BUDDYCLOUD_V1).
                t(@opts.actor)
        pubsubEl.up()

    iqType: ->
        throw new TypeError("Unimplemented request")

    pubsubChild: ->
        throw new TypeError("Unimplemented reply")

    decodeReply: (stanza) ->
        @results = []
        pubsubEl = stanza?.getChild('pubsub', @xmlns)
        if pubsubEl? and @decodeReplyEl?
            for child in pubsubEl.children
                unless typeof child is 'string'
                    @decodeReplyEl child
        @results

class CreateNode extends PubsubRequest
    iqType: ->
        'set'

    pubsubChild: ->
        new xmpp.Element('create', node: @opts.node)

class Publish extends PubsubRequest
    iqType: ->
        'set'

    pubsubChild: ->
        publishEl = new xmpp.Element('publish', node: @opts.node)
        for item in @opts.items
            itemAttrs = {}
            itemAttrs.id ?= item.id
            publishEl.c('item', itemAttrs).
                cnode(item.el)
        publishEl

class RetractItems extends PubsubRequest
    iqType: ->
        'set'

    pubsubChild: ->
        publishEl = new xmpp.Element('retract', node: @opts.node)
        for item in @opts.items
            publishEl.c('item', { id: item.id })
        publishEl

class Subscribe extends PubsubRequest
    iqType: ->
        'set'

    pubsubChild: ->
        new xmpp.Element('subscribe', node: @opts.node, jid: @opts.actor)

    decodeReplyEl: (el) ->
        if el.is('subscription', @xmlns) and
           el.attrs.node is @opts.node
            @results.user ?= el.attrs.jid or @opts.actor
            @results.subscription ?= el.attrs.subscription or 'subscribed'

    localPushData: ->
        [{
            type: 'subscription'
            node: @opts.node
            user: @results.user
            listener: @myJid
            subscription: @results.subscription
        }]

class Unsubscribe extends PubsubRequest
    iqType: ->
        'set'

    pubsubChild: ->
        new xmpp.Element('unsubscribe', node: @opts.node)

    localPushData: ->
        [{
            type: 'subscription'
            node: @opts.node
            user: @opts.actor
            subscription: 'unsubscribed'
        }]

class RetrieveItems extends PubsubRequest
    iqType: ->
        'get'

    pubsubChild: ->
        new xmpp.Element('items', node: @opts.node)

    decodeReplyEl: (el) ->
        if el.is('items', @xmlns)
            for itemEl in el.getChildren('item')
                @results.push
                    id: itemEl.attrs.id
                    el: itemEl.children.filter((child) ->
                        child isnt 'string'
                    )[0]

class PubsubOwnerRequest extends PubsubRequest
    xmlns: NS.PUBSUB_OWNER

class RetrieveNodeSubscriptions extends PubsubOwnerRequest
    iqType: ->
        'get'

    pubsubChild: ->
        new xmpp.Element('subscriptions', node: @opts.node)

    decodeReplyEl: (el) ->
        if el.is('subscriptions', @xmlns)
            for subscriptionEl in el.getChildren('subscription')
                @results.push
                    jid: subscriptionEl.attrs.jid
                    subscription: subscriptionEl.attrs.subscription

class RetrieveNodeAffiliations extends PubsubOwnerRequest
    iqType: ->
        'get'

    pubsubChild: ->
        new xmpp.Element('affiliations', node: @opts.node)

    decodeReplyEl: (el) ->
        if el.is('affiliations', @xmlns)
            for affiliationEl in el.getChildren('affiliation')
                @results.push
                    jid: affiliationEl.attrs.jid
                    affiliation: affiliationEl.attrs.affiliation

class ManageNodeSubscriptions extends PubsubOwnerRequest
    iqType: ->
        'set'

    pubsubChild: ->
        subscriptionsEl = new xmpp.Element('subscriptions', node: @opts.node)
        for subscription in @opts.subscriptions
            subscriptionsEl.c 'subscription',
                jid: subscription.user
                subscription: subscription.subscription
        subscriptionsEl

class ManageNodeAffiliations extends PubsubOwnerRequest
    iqType: ->
        'set'

    pubsubChild: ->
        affiliationsEl = new xmpp.Element('affiliations', node: @opts.node)
        for affiliation in @opts.affiliations
            affiliationsEl.c 'affiliation',
                jid: affiliation.user
                affiliation: affiliation.affiliation
        affiliationsEl

class RetrieveNodeConfiguration extends PubsubOwnerRequest
    iqType: ->
        'get'

    pubsubChild: ->
        new xmpp.Element('configure', node: @opts.node)

    decodeReplyEl: (el) ->
        if el.is('configure', @xmlns)
            xEl = el.getChild('x', NS.DATA)
            form = xEl and forms.fromXml(xEl)
            @results.config ?= form and forms.formToConfig(form)

class ManageNodeConfiguration extends PubsubOwnerRequest
    iqType: ->
        'set'

    pubsubChild: ->
        # TODO: form type should not be "result" but "submit" here
        new xmpp.Element('configure', node: @opts.node).
            cnode(forms.configToForm(@req.config).toXml())


REQUESTS =
    'browse-node-info': exports.DiscoverInfo
    'browse-info': exports.DiscoverInfo
    'create-node': CreateNode
    'publish-node-items': Publish
    'subscribe-node': Subscribe
    'unsubscribe-node': Unsubscribe
    'retrieve-node-items': RetrieveItems
    'retract-node-items': RetractItems
    'retrieve-node-subscriptions': RetrieveNodeSubscriptions
    'retrieve-node-affiliations': RetrieveNodeAffiliations
    'manage-node-subscriptions': ManageNodeSubscriptions
    'manage-node-affiliations': ManageNodeAffiliations
    'retrieve-node-configuration': RetrieveNodeConfiguration
    'manage-node-configuration': ManageNodeConfiguration

exports.byOperation = (opName) ->
    REQUESTS[opName]
