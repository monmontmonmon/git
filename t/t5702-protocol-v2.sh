#!/bin/sh

test_description='test git wire-protocol version 2'

TEST_NO_CREATE_REPO=1

. ./test-lib.sh

# Test protocol v2 with 'git://' transport
#
. "$TEST_DIRECTORY"/lib-git-daemon.sh
start_git_daemon --export-all --enable=receive-pack
daemon_parent=$GIT_DAEMON_DOCUMENT_ROOT_PATH/parent

test_expect_success 'create repo to be served by git-daemon' '
	git init "$daemon_parent" &&
	test_commit -C "$daemon_parent" one
'

test_expect_success 'list refs with git:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote --symref "$GIT_DAEMON_URL/parent" >actual &&

	# Client requested to use protocol v2
	grep "git> .*\\\0\\\0version=2.*\\\0$" log &&
	# Server responded using protocol v2
	grep "git< version 2" log &&

	git ls-remote --symref "$GIT_DAEMON_URL/parent" >expect &&
	test_cmp expect actual
'

test_expect_success 'ref advertisment is filtered with ls-remote using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote "$GIT_DAEMON_URL/parent" master >actual &&

	cat >expect <<-EOF &&
	$(git -C "$daemon_parent" rev-parse refs/heads/master)$(printf "\t")refs/heads/master
	EOF

	test_cmp expect actual
'

test_expect_success 'clone with git:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		clone "$GIT_DAEMON_URL/parent" daemon_child &&

	git -C daemon_child log -1 --format=%s >actual &&
	git -C "$daemon_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	grep "clone> .*\\\0\\\0version=2.*\\\0$" log &&
	# Server responded using protocol v2
	grep "clone< version 2" log
'

test_expect_success 'fetch with git:// using protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C "$daemon_parent" two &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C daemon_child -c protocol.version=2 \
		fetch &&

	git -C daemon_child log -1 --format=%s origin/master >actual &&
	git -C "$daemon_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	grep "fetch> .*\\\0\\\0version=2.*\\\0$" log &&
	# Server responded using protocol v2
	grep "fetch< version 2" log
'

test_expect_success 'fetch by hash without tag following with protocol v2 does not list refs' '
	test_when_finished "rm -f log" &&

	test_commit -C "$daemon_parent" two_a &&
	git -C "$daemon_parent" rev-parse two_a >two_a_hash &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C daemon_child -c protocol.version=2 \
		fetch --no-tags origin $(cat two_a_hash) &&

	grep "fetch< version 2" log &&
	! grep "fetch> command=ls-refs" log
'

test_expect_success 'pull with git:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C daemon_child -c protocol.version=2 \
		pull &&

	git -C daemon_child log -1 --format=%s >actual &&
	git -C "$daemon_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	grep "fetch> .*\\\0\\\0version=2.*\\\0$" log &&
	# Server responded using protocol v2
	grep "fetch< version 2" log
'

test_expect_success 'push with git:// and a config of v2 does not request v2' '
	test_when_finished "rm -f log" &&

	# Till v2 for push is designed, make sure that if a client has
	# protocol.version configured to use v2, that the client instead falls
	# back and uses v0.

	test_commit -C daemon_child three &&

	# Push to another branch, as the target repository has the
	# master branch checked out and we cannot push into it.
	GIT_TRACE_PACKET="$(pwd)/log" git -C daemon_child -c protocol.version=2 \
		push origin HEAD:client_branch &&

	git -C daemon_child log -1 --format=%s >actual &&
	git -C "$daemon_parent" log -1 --format=%s client_branch >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	! grep "push> .*\\\0\\\0version=2\\\0$" log &&
	# Server responded using protocol v2
	! grep "push< version 2" log
'

stop_git_daemon

# Test protocol v2 with 'file://' transport
#
test_expect_success 'create repo to be served by file:// transport' '
	git init file_parent &&
	test_commit -C file_parent one
'

test_expect_success 'list refs with file:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote --symref "file://$(pwd)/file_parent" >actual &&

	# Server responded using protocol v2
	grep "git< version 2" log &&

	git ls-remote --symref "file://$(pwd)/file_parent" >expect &&
	test_cmp expect actual
'

test_expect_success 'ref advertisment is filtered with ls-remote using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote "file://$(pwd)/file_parent" master >actual &&

	cat >expect <<-EOF &&
	$(git -C file_parent rev-parse refs/heads/master)$(printf "\t")refs/heads/master
	EOF

	test_cmp expect actual
'

test_expect_success 'server-options are sent when using ls-remote' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		ls-remote -o hello -o world "file://$(pwd)/file_parent" master >actual &&

	cat >expect <<-EOF &&
	$(git -C file_parent rev-parse refs/heads/master)$(printf "\t")refs/heads/master
	EOF

	test_cmp expect actual &&
	grep "server-option=hello" log &&
	grep "server-option=world" log
'

test_expect_success 'warn if using server-option with ls-remote with legacy protocol' '
	test_must_fail env GIT_TEST_PROTOCOL_VERSION=0 git -c protocol.version=0 \
		ls-remote -o hello -o world "file://$(pwd)/file_parent" master 2>err &&

	test_i18ngrep "see protocol.version in" err &&
	test_i18ngrep "server options require protocol version 2 or later" err
'

test_expect_success 'clone with file:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		clone "file://$(pwd)/file_parent" file_child &&

	git -C file_child log -1 --format=%s >actual &&
	git -C file_parent log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Server responded using protocol v2
	grep "clone< version 2" log &&

	# Client sent ref-prefixes to filter the ref-advertisement
	grep "ref-prefix HEAD" log &&
	grep "ref-prefix refs/heads/" log &&
	grep "ref-prefix refs/tags/" log
'

test_expect_success 'fetch with file:// using protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C file_parent two &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C file_child -c protocol.version=2 \
		fetch origin &&

	git -C file_child log -1 --format=%s origin/master >actual &&
	git -C file_parent log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Server responded using protocol v2
	grep "fetch< version 2" log
'

test_expect_success 'ref advertisment is filtered during fetch using protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C file_parent three &&
	git -C file_parent branch unwanted-branch three &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C file_child -c protocol.version=2 \
		fetch origin master &&

	git -C file_child log -1 --format=%s origin/master >actual &&
	git -C file_parent log -1 --format=%s >expect &&
	test_cmp expect actual &&

	grep "refs/heads/master" log &&
	! grep "refs/heads/unwanted-branch" log
'

test_expect_success 'server-options are sent when fetching' '
	test_when_finished "rm -f log" &&

	test_commit -C file_parent four &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C file_child -c protocol.version=2 \
		fetch -o hello -o world origin master &&

	git -C file_child log -1 --format=%s origin/master >actual &&
	git -C file_parent log -1 --format=%s >expect &&
	test_cmp expect actual &&

	grep "server-option=hello" log &&
	grep "server-option=world" log
'

test_expect_success 'warn if using server-option with fetch with legacy protocol' '
	test_when_finished "rm -rf temp_child" &&

	git init temp_child &&

	test_must_fail env GIT_TEST_PROTOCOL_VERSION=0 git -C temp_child -c protocol.version=0 \
		fetch -o hello -o world "file://$(pwd)/file_parent" master 2>err &&

	test_i18ngrep "see protocol.version in" err &&
	test_i18ngrep "server options require protocol version 2 or later" err
'

test_expect_success 'server-options are sent when cloning' '
	test_when_finished "rm -rf log myclone" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -c protocol.version=2 \
		clone --server-option=hello --server-option=world \
		"file://$(pwd)/file_parent" myclone &&

	grep "server-option=hello" log &&
	grep "server-option=world" log
'

test_expect_success 'warn if using server-option with clone with legacy protocol' '
	test_when_finished "rm -rf myclone" &&

	test_must_fail env GIT_TEST_PROTOCOL_VERSION=0 git -c protocol.version=0 \
		clone --server-option=hello --server-option=world \
		"file://$(pwd)/file_parent" myclone 2>err &&

	test_i18ngrep "see protocol.version in" err &&
	test_i18ngrep "server options require protocol version 2 or later" err
'

test_expect_success 'upload-pack respects config using protocol v2' '
	git init server &&
	write_script server/.git/hook <<-\EOF &&
		touch hookout
		"$@"
	EOF
	test_commit -C server one &&

	test_config_global uploadpack.packobjectshook ./hook &&
	test_path_is_missing server/.git/hookout &&
	git -c protocol.version=2 clone "file://$(pwd)/server" client &&
	test_path_is_file server/.git/hookout
'

test_expect_success 'setup filter tests' '
	rm -rf server client &&
	git init server &&

	# 1 commit to create a file, and 1 commit to modify it
	test_commit -C server message1 a.txt &&
	test_commit -C server message2 a.txt &&
	git -C server config protocol.version 2 &&
	git -C server config uploadpack.allowfilter 1 &&
	git -C server config uploadpack.allowanysha1inwant 1 &&
	git -C server config protocol.version 2
'

test_expect_success 'partial clone' '
	GIT_TRACE_PACKET="$(pwd)/trace" git -c protocol.version=2 \
		clone --filter=blob:none "file://$(pwd)/server" client &&
	grep "version 2" trace &&

	# Ensure that the old version of the file is missing
	git -C client rev-list --quiet --objects --missing=print master \
		>observed.oids &&
	grep "$(git -C server rev-parse message1:a.txt)" observed.oids &&

	# Ensure that client passes fsck
	git -C client fsck
'

test_expect_success 'dynamically fetch missing object' '
	rm "$(pwd)/trace" &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		cat-file -p $(git -C server rev-parse message1:a.txt) &&
	grep "version 2" trace
'

test_expect_success 'when dynamically fetching missing object, do not list refs' '
	! grep "git> command=ls-refs" trace
'

test_expect_success 'partial fetch' '
	rm -rf client "$(pwd)/trace" &&
	git init client &&
	SERVER="file://$(pwd)/server" &&
	test_config -C client extensions.partialClone "$SERVER" &&

	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch --filter=blob:none "$SERVER" master:refs/heads/other &&
	grep "version 2" trace &&

	# Ensure that the old version of the file is missing
	git -C client rev-list --quiet --objects --missing=print other \
		>observed.oids &&
	grep "$(git -C server rev-parse message1:a.txt)" observed.oids &&

	# Ensure that client passes fsck
	git -C client fsck
'

test_expect_success 'do not advertise filter if not configured to do so' '
	SERVER="file://$(pwd)/server" &&

	rm "$(pwd)/trace" &&
	git -C server config uploadpack.allowfilter 1 &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -c protocol.version=2 \
		ls-remote "$SERVER" &&
	grep "fetch=.*filter" trace &&

	rm "$(pwd)/trace" &&
	git -C server config uploadpack.allowfilter 0 &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -c protocol.version=2 \
		ls-remote "$SERVER" &&
	grep "fetch=" trace >fetch_capabilities &&
	! grep filter fetch_capabilities
'

test_expect_success 'partial clone warns if filter is not advertised' '
	rm -rf client &&
	git -C server config uploadpack.allowfilter 0 &&
	git -c protocol.version=2 \
		clone --filter=blob:none "file://$(pwd)/server" client 2>err &&
	test_i18ngrep "filtering not recognized by server, ignoring" err
'

test_expect_success 'even with handcrafted request, filter does not work if not advertised' '
	git -C server config uploadpack.allowfilter 0 &&

	# Custom request that tries to filter even though it is not advertised.
	test-tool pkt-line pack >in <<-EOF &&
	command=fetch
	0001
	want $(git -C server rev-parse master)
	filter blob:none
	0000
	EOF

	test_must_fail test-tool -C server serve-v2 --stateless-rpc \
		<in >/dev/null 2>err &&
	grep "unexpected line: .filter blob:none." err &&

	# Exercise to ensure that if advertised, filter works
	git -C server config uploadpack.allowfilter 1 &&
	test-tool -C server serve-v2 --stateless-rpc <in >/dev/null
'

test_expect_success 'default refspec is used to filter ref when fetchcing' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C file_child -c protocol.version=2 \
		fetch origin &&

	git -C file_child log -1 --format=%s three >actual &&
	git -C file_parent log -1 --format=%s three >expect &&
	test_cmp expect actual &&

	grep "ref-prefix refs/heads/" log &&
	grep "ref-prefix refs/tags/" log
'

test_expect_success 'fetch supports various ways of have lines' '
	rm -rf server client trace &&
	git init server &&
	test_commit -C server dwim &&
	TREE=$(git -C server rev-parse HEAD^{tree}) &&
	git -C server tag exact \
		$(git -C server commit-tree -m a "$TREE") &&
	git -C server tag dwim-unwanted \
		$(git -C server commit-tree -m b "$TREE") &&
	git -C server tag exact-unwanted \
		$(git -C server commit-tree -m c "$TREE") &&
	git -C server tag prefix1 \
		$(git -C server commit-tree -m d "$TREE") &&
	git -C server tag prefix2 \
		$(git -C server commit-tree -m e "$TREE") &&
	git -C server tag fetch-by-sha1 \
		$(git -C server commit-tree -m f "$TREE") &&
	git -C server tag completely-unrelated \
		$(git -C server commit-tree -m g "$TREE") &&

	git init client &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch "file://$(pwd)/server" \
		dwim \
		refs/tags/exact \
		refs/tags/prefix*:refs/tags/prefix* \
		"$(git -C server rev-parse fetch-by-sha1)" &&

	# Ensure that the appropriate prefixes are sent (using a sample)
	grep "fetch> ref-prefix dwim" trace &&
	grep "fetch> ref-prefix refs/heads/dwim" trace &&
	grep "fetch> ref-prefix refs/tags/prefix" trace &&

	# Ensure that the correct objects are returned
	git -C client cat-file -e $(git -C server rev-parse dwim) &&
	git -C client cat-file -e $(git -C server rev-parse exact) &&
	git -C client cat-file -e $(git -C server rev-parse prefix1) &&
	git -C client cat-file -e $(git -C server rev-parse prefix2) &&
	git -C client cat-file -e $(git -C server rev-parse fetch-by-sha1) &&
	test_must_fail git -C client cat-file -e \
		$(git -C server rev-parse dwim-unwanted) &&
	test_must_fail git -C client cat-file -e \
		$(git -C server rev-parse exact-unwanted) &&
	test_must_fail git -C client cat-file -e \
		$(git -C server rev-parse completely-unrelated)
'

test_expect_success 'fetch supports include-tag and tag following' '
	rm -rf server client trace &&
	git init server &&

	test_commit -C server to_fetch &&
	git -C server tag -a annotated_tag -m message &&

	git init client &&
	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch "$(pwd)/server" to_fetch:to_fetch &&

	grep "fetch> ref-prefix to_fetch" trace &&
	grep "fetch> ref-prefix refs/tags/" trace &&
	grep "fetch> include-tag" trace &&

	git -C client cat-file -e $(git -C client rev-parse annotated_tag)
'

test_expect_success 'upload-pack respects client shallows' '
	rm -rf server client trace &&

	git init server &&
	test_commit -C server base &&
	test_commit -C server client_has &&

	git clone --depth=1 "file://$(pwd)/server" client &&

	# Add extra commits to the client so that the whole fetch takes more
	# than 1 request (due to negotiation)
	test_commit_bulk -C client --id=c 32 &&

	git -C server checkout -b newbranch base &&
	test_commit -C server client_wants &&

	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch origin newbranch &&
	# Ensure that protocol v2 is used
	grep "fetch< version 2" trace
'

test_expect_success 'ensure that multiple fetches in same process from a shallow repo works' '
	rm -rf server client trace &&

	test_create_repo server &&
	test_commit -C server one &&
	test_commit -C server two &&
	test_commit -C server three &&
	git clone --shallow-exclude two "file://$(pwd)/server" client &&

	git -C server tag -a -m "an annotated tag" twotag two &&

	# Triggers tag following (thus, 2 fetches in one process)
	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch --shallow-exclude one origin &&
	# Ensure that protocol v2 is used
	grep "fetch< version 2" trace
'

test_expect_success 'deepen-relative' '
	rm -rf server client trace &&

	test_create_repo server &&
	test_commit -C server one &&
	test_commit -C server two &&
	test_commit -C server three &&
	git clone --depth 1 "file://$(pwd)/server" client &&
	test_commit -C server four &&

	# Sanity check that only "three" is downloaded
	git -C client log --pretty=tformat:%s master >actual &&
	echo three >expected &&
	test_cmp expected actual &&

	GIT_TRACE_PACKET="$(pwd)/trace" git -C client -c protocol.version=2 \
		fetch --deepen=1 origin &&
	# Ensure that protocol v2 is used
	grep "fetch< version 2" trace &&

	git -C client log --pretty=tformat:%s origin/master >actual &&
	cat >expected <<-\EOF &&
	four
	three
	two
	EOF
	test_cmp expected actual
'

# Test protocol v2 with 'http://' transport
#
. "$TEST_DIRECTORY"/lib-httpd.sh
start_httpd

test_expect_success 'create repo to be served by http:// transport' '
	git init "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" config http.receivepack true &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" one
'

test_expect_success 'clone with http:// using protocol v2' '
	test_when_finished "rm -f log" &&

	GIT_TRACE_PACKET="$(pwd)/log" GIT_TRACE_CURL="$(pwd)/log" git -c protocol.version=2 \
		clone "$HTTPD_URL/smart/http_parent" http_child &&

	git -C http_child log -1 --format=%s >actual &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Client requested to use protocol v2
	grep "Git-Protocol: version=2" log &&
	# Server responded using protocol v2
	grep "git< version 2" log &&
	# Verify that the chunked encoding sending codepath is NOT exercised
	! grep "Send header: Transfer-Encoding: chunked" log
'

test_expect_success 'clone big repository with http:// using protocol v2' '
	test_when_finished "rm -f log" &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/big" &&
	# Ensure that the list of wants is greater than http.postbuffer below
	for i in $(test_seq 1 1500)
	do
		# do not use here-doc, because it requires a process
		# per loop iteration
		echo "commit refs/heads/too-many-refs-$i" &&
		echo "committer git <git@example.com> $i +0000" &&
		echo "data 0" &&
		echo "M 644 inline bla.txt" &&
		echo "data 4" &&
		echo "bla"
	done | git -C "$HTTPD_DOCUMENT_ROOT_PATH/big" fast-import &&

	GIT_TRACE_PACKET="$(pwd)/log" GIT_TRACE_CURL="$(pwd)/log" git \
		-c protocol.version=2 -c http.postbuffer=65536 \
		clone "$HTTPD_URL/smart/big" big_child &&

	# Client requested to use protocol v2
	grep "Git-Protocol: version=2" log &&
	# Server responded using protocol v2
	grep "git< version 2" log &&
	# Verify that the chunked encoding sending codepath is exercised
	grep "Send header: Transfer-Encoding: chunked" log
'

test_expect_success 'fetch with http:// using protocol v2' '
	test_when_finished "rm -f log" &&

	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" two &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C http_child -c protocol.version=2 \
		fetch &&

	git -C http_child log -1 --format=%s origin/master >actual &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" log -1 --format=%s >expect &&
	test_cmp expect actual &&

	# Server responded using protocol v2
	grep "git< version 2" log
'

test_expect_success 'fetch from namespaced repo respects namespaces' '
	test_when_finished "rm -f log" &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" one &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" two &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" \
		update-ref refs/namespaces/ns/refs/heads/master one &&

	GIT_TRACE_PACKET="$(pwd)/log" git -C http_child -c protocol.version=2 \
		fetch "$HTTPD_URL/smart_namespace/nsrepo" \
		refs/heads/master:refs/heads/theirs &&

	# Server responded using protocol v2
	grep "fetch< version 2" log &&

	git -C "$HTTPD_DOCUMENT_ROOT_PATH/nsrepo" rev-parse one >expect &&
	git -C http_child rev-parse theirs >actual &&
	test_cmp expect actual
'

test_expect_success 'push with http:// and a config of v2 does not request v2' '
	test_when_finished "rm -f log" &&
	# Till v2 for push is designed, make sure that if a client has
	# protocol.version configured to use v2, that the client instead falls
	# back to previous versions.

	test_commit -C http_child three &&

	# Push to another branch, as the target repository has the
	# master branch checked out and we cannot push into it.
	GIT_TRACE_PACKET="$(pwd)/log" git -C http_child -c protocol.version=2 \
		push origin HEAD:client_branch &&

	git -C http_child log -1 --format=%s >actual &&
	git -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" log -1 --format=%s client_branch >expect &&
	test_cmp expect actual &&

	# Server responded with version 1
	grep "git< version 1" log
'

test_expect_success 'when server sends "ready", expect DELIM' '
	rm -rf "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" http_child &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" one &&

	git clone "$HTTPD_URL/smart/http_parent" http_child &&

	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" two &&

	# After "ready" in the acknowledgments section, pretend that a FLUSH
	# (0000) was sent instead of a DELIM (0001).
	printf "/ready/,$ s/0001/0000/" \
		>"$HTTPD_ROOT_PATH/one-time-sed" &&

	test_must_fail git -C http_child -c protocol.version=2 \
		fetch "$HTTPD_URL/one_time_sed/http_parent" 2> err &&
	test_i18ngrep "expected packfile to be sent after .ready." err
'

test_expect_success 'when server does not send "ready", expect FLUSH' '
	rm -rf "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" http_child log &&

	git init "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" one &&

	git clone "$HTTPD_URL/smart/http_parent" http_child &&

	test_commit -C "$HTTPD_DOCUMENT_ROOT_PATH/http_parent" two &&

	# Create many commits to extend the negotiation phase across multiple
	# requests, so that the server does not send "ready" in the first
	# request.
	test_commit_bulk -C http_child --id=c 32 &&

	# After the acknowledgments section, pretend that a DELIM
	# (0001) was sent instead of a FLUSH (0000).
	printf "/acknowledgments/,$ s/0000/0001/" \
		>"$HTTPD_ROOT_PATH/one-time-sed" &&

	test_must_fail env GIT_TRACE_PACKET="$(pwd)/log" git -C http_child \
		-c protocol.version=2 \
		fetch "$HTTPD_URL/one_time_sed/http_parent" 2> err &&
	grep "fetch< .*acknowledgments" log &&
	! grep "fetch< .*ready" log &&
	test_i18ngrep "expected no other sections to be sent after no .ready." err
'

configure_exclusion () {
	git -C "$1" hash-object "$2" >objh &&
	git -C "$1" pack-objects "$HTTPD_DOCUMENT_ROOT_PATH/mypack" <objh >packh &&
	git -C "$1" config --add \
		"uploadpack.blobpackfileuri" \
		"$(cat objh) $(cat packh) $HTTPD_URL/dumb/mypack-$(cat packh).pack" &&
	cat objh
}

test_expect_success 'part of packfile response provided as URI' '
	P="$HTTPD_DOCUMENT_ROOT_PATH/http_parent" &&
	rm -rf "$P" http_child log &&

	git init "$P" &&
	git -C "$P" config "uploadpack.allowsidebandall" "true" &&

	echo my-blob >"$P/my-blob" &&
	git -C "$P" add my-blob &&
	echo other-blob >"$P/other-blob" &&
	git -C "$P" add other-blob &&
	git -C "$P" commit -m x &&

	configure_exclusion "$P" my-blob >h &&
	configure_exclusion "$P" other-blob >h2 &&

	GIT_TRACE=1 GIT_TRACE_PACKET="$(pwd)/log" GIT_TEST_SIDEBAND_ALL=1 \
	git -c protocol.version=2 \
		-c fetch.uriprotocols=http,https \
		clone "$HTTPD_URL/smart/http_parent" http_child &&

	# Ensure that my-blob and other-blob are in separate packfiles.
	for idx in http_child/.git/objects/pack/*.idx
	do
		git verify-pack --verbose $idx >out &&
		{
			grep "^[0-9a-f]\{16,\} " out || :
		} >out.objectlist &&
		if test_line_count = 1 out.objectlist
		then
			if grep $(cat h) out
			then
				>hfound
			fi &&
			if grep $(cat h2) out
			then
				>h2found
			fi
		fi
	done &&
	test -f hfound &&
	test -f h2found &&

	# Ensure that there are exactly 6 files (3 .pack and 3 .idx).
	ls http_child/.git/objects/pack/* >filelist &&
	test_line_count = 6 filelist
'

test_done
