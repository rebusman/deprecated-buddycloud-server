{ TestServer } = require('./test_server')
should = require('should')

describe "Creating a channel", ->
    server = new TestServer()

    it "must be possible for a local user", (done) ->
        iq = server.makeIq("set", "test@example.org", "buddycloud.example.org", "create1")
            .c("pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            .c("create", node: "/user/test@example.org/posts")
            .root()
        server.doTest iq, "got-iq-result-create1", done, (iq) ->

    it "must fail if a node already exists", (done) ->
        iq = server.makeIq("set", "test@example.org", "buddycloud.example.org", "create2")
            .c("pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            .c("create", node: "/user/test@example.org/posts")
            .root()
        server.doTest iq, "got-iq-error-create2", done, (iq) ->
            iq.children.should.have.length 1
            err = iq.children[0]
            err.name.should.equal "error"
            err.attrs.should.have.property "type", "cancel"
            should.exist(err.getChild("conflict", "urn:ietf:params:xml:ns:xmpp-stanzas"))

    it "requires a node ID", (done) ->
        iq = server.makeIq("set", "test@example.org", "buddycloud.example.org", "create3")
            .c("pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            .c("create")
            .root()
        server.doTest iq, "got-iq-error-create3", done, (iq) ->
            iq.children.should.have.length 1
            err = iq.children[0]
            err.name.should.equal "error"
            err.attrs.should.have.property "type", "modify"
            should.exist(err.getChild("not-acceptable", "urn:ietf:params:xml:ns:xmpp-stanzas"))
            should.exist(err.getChild("nodeid-required", "http://jabber.org/protocol/pubsub#errors"))

    it "must support node configuration", (done) ->
        form = server.makeForm "submit", "http://jabber.org/protocol/pubsub#node_config",
            "pubsub#title": "Status for test@example.org"
            "pubsub#description": "What test@example.org is currently doing"
        iq = server.makeIq("set", "test@example.org", "buddycloud.example.org", "create4")
            .c("pubsub", xmlns: "http://jabber.org/protocol/pubsub")
            .c("create", node: "/user/test@example.org/status").up()
            .c("configure").cnode(form)
            .root()
        server.doTest iq, "got-iq-result-create4", done, (iq) ->

    it "must make nodes discoverable", (done) ->
        iq = server.makeIq("get", "test@example.org", "buddycloud.example.org", "disco1")
            .c("query", xmlns: "http://jabber.org/protocol/disco#info", node: "/user/test@example.org/status")
            .root()
        server.doTest iq, "got-iq-result-disco1", done, (iq) ->
            iq.children.should.have.length 1

            disco = server.parseDiscoInfo iq
            expectedIdentities = [
                { category: "pubsub", type: "leaf" },
                { category: "pubsub", type: "channel"}
            ]
            for identity in expectedIdentities
                disco.identities.should.includeEql identity

            disco.should.have.property "form"
            disco.form.should.have.property "pubsub#title", "Status for test@example.org"
            disco.form.should.have.property "pubsub#description", "What test@example.org is currently doing"
