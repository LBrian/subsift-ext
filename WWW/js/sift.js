// AJAX functionality for Submission Sifting demo

// Note: This script is designed to be (relatively) quickly understood rather than as a model of elegance.

var getWithToken = function(url) {
    var user_id = $("#user_id").val();
    var token = $("#token").val();
    if (user_id == '' || token == '') {
        alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
        return false;
    }
    
    $.ajax({
        type: 'GET',
        url: url,
        contentType: "application/x-www-form-urlencoded; charset=utf-8",
        data: null,
        dataType: "text",
        beforeSend: function (req) {
            req.setRequestHeader("Token", token);
        },
        success: function(data, textStatus, req) {
        },
        error: function(req, textStatus, errorThrown) {
            var text = (req == null) ? '' : req.responseText;
            alert("Status: " + req.status + "\n\n" + text);
        }
    });
    
    return false;
};



$(function() {

    // initialise jQueryUI tabs behaviour (makes bulleted lists behave as tabs)
    var tabsA = $('#tabsA').tabs();
    var tabsB = $('#tabsB').tabs();
    var tabsC = $('#tabsC').tabs();

    //hover states on the static widgets
    $("input[type='submit'], button").hover(
        function() { $(this).addClass('ui-state-hover'); }, 
        function() { $(this).removeClass('ui-state-hover'); }
    );
    

    //--------------------------------------------------------------------------------------------------
    // TABS A

    $("#tabsA").bind('tabsselect', function(event, ui) {
        if (ui.index === 4) {
            // load A.5 drop-down items if not already done so
            if ($('#reviewer_documents').val() == null) {
                $("#formA5_update_options").click();
            }
        }
        else if (ui.index === 5) {
            // load A.6 drop-down items if not already done so
            if ($('#reviewer_profiles').val() == null) {
                $("#formA6_update_options").click();
            }
        }
    });


    $("#formA1").submit(function() {
        $("#resultA1").empty();
        var text = $("#names_list").val();
        var refresh = ($("#refresh:checked").val() === undefined) ? false : true;
        if (refresh) {
            if (!confirm("This can take 5-10 seconds per name. A new page is not displayed until the search has finished.\n\nDo not click Submit again or it will take even longer!")) {
                return false;
            }
        }
        $.ajax({
            type: 'POST',
            url: 'search.json',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: {
                'names_list': text,
                'refresh':  (refresh ? '1' : '0')
            },
            dataType: "json",
            success: function(rawdata, textStatus, req) {
                data = $.parseJSON(req.responseText);

                $('#resultA1').text(data);
                
                var fb = '';
                if (data.missing != null) {
                    $.each(data.missing, 
                        function(i, item) {
                            fb += '<li style="color: red;">' + item + '</li>';
                        }
                    );
                    if (fb != '') {
                        fb = '<strong>WARNING:</strong> ' + 
                             'Before submitting, you must supply an author name and DBLP (or similar) author publications page URL for the following names:<br/>' + 
                             '<ul>' + fb + '</ul>';
                    }
                }
                $('#A2_feedback_from_A1').html(fb);
                
                var list = '';
                if (data.list != null) {
                    $.each(data.list, 
                        function(i, item) {
                            list += item.name + ', ' + item.description + ', ' + item.uri + '\n';
                        }
                    );
                }
                $("#pages_list").text(list);
                
                tabsA.tabs('select', 1);
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultA1").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    });    


    $("#formA2").submit(function() {
        $("#resultA2").empty();
        var text = $("#pages_list").val();
        $.ajax({
            type: 'POST',
            url: 'disambiguate',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: {
                'pages_list': text,
            },
            dataType: "html",
            success: function(data, textStatus, req) {
                $("#disambiguation").html(data);
                tabsA.tabs('select', 2);
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultA2").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    });    


    $("#formA3").submit(function() {
        $("#resultA3").empty();
        var params = $(this).serializeArray();
        $.ajax({
            type: 'POST',
            url: 'restrict',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: params,
            dataType: "text",
            success: function(data, textStatus, req) {
                $("#bookmarks_list").text(data);
                tabsA.tabs('select', 3);
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultA3").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    });    
    
        
    $("#formA4").submit(function() {
        $("#resultA4").empty();

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var folder_id = $("#reviewers_folder").val();
        var bookmarks_url = site.url + '/' + user_id + '/bookmarks/' + folder_id;
        var documents_url = site.url + '/' + user_id + '/documents/' + folder_id;

        var items_list = $('#bookmarks_list').val();

        var importDocuments = function() {
            $.ajax({
                type: 'POST',
                url: documents_url + '/import/' + folder_id,
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: null,
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    // folder created, so can go ahead and queue bookmarks for harvesting
                    alert('URLs queued for harvesting. This usually takes 10-15 minutes.');
                    $("#formA5_update_options").click();
                    tabsA.tabs('select', 4);
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA4").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };
        var replaceDocuments = function() {
            $.ajax({
                type: 'DELETE',
                url: documents_url + '/items',
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: null,
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    // all documents in folder deleted, so can go ahead and import
                    importDocuments();
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA4").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };
        var createDocuments = function() {
            $.ajax({
                type: 'POST',
                url: documents_url,
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'description': 'created by Submission Sifting demo',
                    'mode': 'private'
                },
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    // folder created, so can go ahead and queue bookmarks for harvesting
                    importDocuments();
                },
                error: function(req, textStatus, errorThrown) {
                    if (req.status == 403) {
                        // folder exists, so clear it out (not asking user if okay)
                        replaceDocuments();
                    } else {
                        var text = (req == null) ? '' : req.responseText;
                        $("#resultA4").text("Status: " + req.status + "\n\n" + text);
                    }
                }
            });
        };
        
        var storeBookmarks = function() {
            $.ajax({
                type: 'POST',
                url: bookmarks_url + '/items',
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'items_list': items_list
                },
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    // folder created, so can go ahead and store bookmarks
                    createDocuments();
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA4").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };
        var createBookmarks = function() {
            $.ajax({
                type: 'POST',
                url: bookmarks_url,
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'description': 'created by Submission Sifting demo',
                    'mode': 'private'
                },
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    // folder created, so can go ahead and store bookmarks
                    storeBookmarks();
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA4").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };
        var replaceBookmarks = function() {
            $.ajax({
                type: 'DELETE',
                url: bookmarks_url + '/items',
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: null,
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    // all bookmarks in folder deleted, so can go ahead and store bookmarks
                    storeBookmarks();
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA4").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };

        var params = $(this).serializeArray();
        $.ajax({
            type: 'HEAD',
            url: bookmarks_url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,// params,
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(data, textStatus, req) {
                // folder exists, so store bookmarks in it
                if (confirm('Overwrite the existing list of reviewers: ' + folder_id + '?')) {
                    replaceBookmarks();
                }
            },
            error: function(req, textStatus, errorThrown) {
                if (req.status == 404) {
                    // folder does not exist, so create it
                    createBookmarks();
                } else {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA4").text("Status: " + req.status + "\n\n" + text);
                }
            }
        });
        return false;
    });
    
    $("#formA5_update_options").click(function() {
        // update drop-down list of documents folder names

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        $("#resultA5").empty();
        var fb='';
        $.ajax({
            type: 'GET',
            url: site.url + '/' + user_id + '/documents.json',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "json",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                data = $.parseJSON(req.responseText);
                if (data.folder != null) {
                    var folder_id = $("#reviewers_folder").val();
                    var options = '';
                    $.each(data.folder, 
                        function(i, item) {
                            options += '<option value="' + item.id + '"' +
                                       ((item.id == folder_id) ? ' selected="selected"' : '') +
                                       '>' + item.id + '</option>';
                        }
                    );
                    $('#reviewer_documents').html(options);
                }
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultA5").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    });

    $("#formA5").submit(function() {
        
        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var folder_id = $("#reviewer_documents").val();
        var profiles_url = site.url + '/' + user_id + '/profiles/' + folder_id;

        $("#resultA5").html('<br/><br/><em>Calculating profiles...</em>');

        var calculateProfile = function(folder_exists) {
            var mode = (($("#public_reviewer_profiles:checked").val() === undefined) ? 'private' : 'public');
            $.ajax({
                type: (folder_exists) ? 'PUT' : 'POST',
                url: profiles_url + '/from/' + folder_id + '.json',
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'mode': mode,
                    'ngrams': '1,2,3',
                    'recalculate': '1'
                },
                dataType: "json",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    var isprivate = (mode === 'private') ? ' <em>(private)</em>' : '';
                    var s = '<br/>' +
                        '<blockquote>' +
                        '<h3 style="margin-top:0px;">Profiles Data: ' + folder_id + '</h3>' +
                        '<p>A profile has been calculated and, if required, can be accessed via the SubSift REST API and Linked Data.</p>' +
                        '<ul>' +
                        '<li><strong>Profile Items via SubSift API:</strong>' + isprivate +
                        '<ul>' +
                        '<li><a href="' + profiles_url + '/items.json?full=1" target="_new">JSON</a></li>' +
                        '<li><a href="' + profiles_url + '/items.terms?full=1" target="_new">Prolog Terms</a></li>' +
                        '<li><a href="' + profiles_url + '/items.rdf?full=1" target="_new">RDF</a></li>' +
                        '<li><a href="' + profiles_url + '/items.xml?full=1" target="_new">XML</a></li>' +
                        '<li><a href="' + profiles_url + '/items.yml?full=1" target="_new">YAML</a></li>' +
                        '</ul>' +
                        '</li>' +
                        '<li><strong>Profile Items via Linked Data:</strong>' + isprivate +
                        '<ul>' +
                        '<li><a href="' + profiles_url + '.rdf">' + profiles_url + '.rdf</a></li>' +
                        '</ul>' +
                        '</li>' +
                        '<ul>' +
                        '</blockquote>' +
                        '<p>If you wish to view, download or publish the profile as a report, proceed to Step 6.<br/>' + 
                        'Otherwise, go straight to Step 1 of "B. Paper Profile Builder" below.</p>';
                    $("#resultA5").html(s);
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA5").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };

        // check if folder already exists and then either create it or recalculate it
        $.ajax({
            type: 'HEAD',
            url: profiles_url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                calculateProfile(true);
            },
            error: function(req, textStatus, errorThrown) {
                if (req.status == 404) {
                    // folder does not exist, so create it
                    calculateProfile(false);
                } else {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA5").text("Status: " + req.status + "\n\n" + text);
                }
            }
        });
        return false;
    });


    $("#formA6_update_options").click(function() {
        // update drop-down list of documents folder names

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var fb='';
        $.ajax({
            type: 'GET',
            url: site.url + '/' + user_id + '/profiles.json',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "json",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                data = $.parseJSON(req.responseText);
                if (data.folder != null) {
                    var folder_id = $("#reviewers_folder").val();
                    var options = '';
                    $.each(data.folder, 
                        function(i, item) {
                            options += '<option value="' + item.id + '"' +
                                       ((item.id == folder_id) ? ' selected="selected"' : '') +
                                       '>' + item.id + '</option>';
                        }
                    );
                    $('#reviewer_profiles').html(options);
                }
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultA6").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    });

    $("#formA6").submit(function() {
        // update drop-down list of documents folder names

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var folder_id = $("#reviewer_profiles").val();
        var reports_url = site.url + '/' + user_id + '/reports/' + folder_id;

        $("#resultA6").html('<br/><br/><em>Generating report...</em>');

        var calculateReports = function() {
            var mode = (($("#public_reviewer_reports:checked").val() === undefined) ? 'private' : 'public');
            $.ajax({
                type: 'POST',
                url: reports_url + '/profiles/' + folder_id,
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'mode': mode,
                    'suppress_response_codes': '1'
                },
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    var isprivate = (mode === 'private') ? ' <em>(private)</em>' : '';
                    var s = '<br/>' +
                        '<blockquote>' +
                        '<h3 style="margin-top:0px;">Reviewer Profiles Report: ' + folder_id + '</h3>' +
                        '<p>A report has been generated and can be accessed at the following URLs.</p>' +
                        '<ul>' +
                        '<li><strong>Report Homepage:</strong>' + isprivate + '<br/>&nbsp; &nbsp;' +
                        '<a href="' + reports_url + '/" target="_new">' + reports_url + '/</a>' +
                        '</li>' +
                        '<li><strong>Report Download:</strong>' + isprivate + '<br/>&nbsp; &nbsp;' +
                        '<a href="' + reports_url + '.zip">' + reports_url + '.zip</a>' +
                        '</li>' +
                        '<ul>' +
                        '</blockquote>';
                    $("#resultA6").html(s);
                    formC1_update_both();
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA6").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };

        // delete any existing reports folder of this name before creating new one
        $.ajax({
            type: 'DELETE',
            url: reports_url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(data, textStatus, req) {
                // reports folder deleted, so go ahead and recreate
                calculateReports();
            },
            error: function(req, textStatus, errorThrown) {
                if (req.status == 404) {
                    // folder did not exist, so just go ahead and create
                    calculateReports();
                } else {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultA6").text("Status: " + req.status + "\n\n" + text);
                }
            }
        });

        return false;
    });

    
    //--------------------------------------------------------------------------------------------------
    // TABS B
    

    $("#tabsB").bind('tabsselect', function(event, ui) {
        if (ui.index === 1) {
            // load B.2 drop-down items if not already done so
            if ($('#abstract_documents').val() == null) {
                $("#formB2_update_options").click();
            }
        }
        else if (ui.index === 2) {
            // load B.3 drop-down items if not already done so
            if ($('#abstract_profiles').val() == null) {
                $("#formB3_update_options").click();
            }
        }
    });


    $("#formB1_change_name").click(function() {
	    $('#abstract_name_subform2').hide();
	    $('#abstract_name_subform1').show();
	    // delete the uploader button objects and handlers
	    $('#file_uploader').html('');
    });

    $("#formB1").submit(function() {

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var folder_id = $("#abstracts_folder").val();
        if (folder_id == "") {
            alert('Enter a name to save the abstracts as.');
            return false;
        }
        
        var documents_url = site.url + '/' + user_id + '/documents/' + folder_id;

        $("#resultB1").empty();

    	var create_uploader = function() {
    	    // hide the name data entry block
    	    $('#abstract_name_subform1').hide();
    	    $('#formB1_abstract_name').html(folder_id);
    	    $('#abstract_name_subform2').show();
    	    // clear out any previous uploader button objects and handlers
    	    $('#file_uploader').html('');
    	    // create uploader button objects and handlers
    	    var uploader = new qq.FileUploader({
                element: $('#file_uploader')[0],
                action: site.url + '/' + user_id + '/documents/' + folder_id + '/items.json',
                multiple: false,
                onSubmit: function(id, fileName){},
                beforeSend: function(req) {
                    var token = $("#token").val();
                    req.setRequestHeader("Token", token);
                },
                onProgress: function(id, fileName, loaded, total){},
                onComplete: function(id, fileName, responseJSON) {
                    $("#formB2_update_options").click();
                    tabsB.tabs('select', 1);
                },
                onCancel: function(id, fileName){},
                template: '<div class="qq-uploader">' + 
                        '<div class="qq-upload-drop-area"><span>Drop files here to upload</span></div>' +
                        '<div class="qq-upload-button ui-button ui-widget ui-state-default ui-corner-all ui-button-text-only" style="padding: 0.2em 0.2em;">Choose File...</div>' +
                        '<ul class="qq-upload-list"></ul>' + 
                     '</div>',
                params: {
                    'param': 'items_list',
                    'full': '1'
                }   //NB. 'param' specifies key to store uploaded file data in when decoding params on server
            });
        };
        var replaceDocuments = function() {
            $.ajax({
                type: 'DELETE',
                url: documents_url + '/items',
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: null,
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    // existing folder emptied out, so record that it is now okay to do an upload
                    create_uploader();
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultB1").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };
        var createDocuments = function() {
            $.ajax({
                type: 'POST',
                url: documents_url,
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'description': 'created by Submission Sifting demo',
                    'mode': 'private'
                },
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    // folder created, so record that it is now okay to do an upload
                    create_uploader();
                },
                error: function(req, textStatus, errorThrown) {
                    if (req.status == 403) {
                        // folder exists, so clear it out (not asking user if okay)
                        replaceDocuments();
                    } else {
                        var text = (req == null) ? '' : req.responseText;
                        $("#resultB1").text("Status: " + req.status + "\n\n" + text);
                    }
                }
            });
        };

        $.ajax({
            type: 'HEAD',
            url: documents_url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(data, textStatus, req) {
                // folder exists, so store abstracts in it
                if (confirm('Overwrite the existing list of abstracts: ' + folder_id + '?')) {
                    replaceDocuments();
                }
            },
            error: function(req, textStatus, errorThrown) {
                if (req.status == 404) {
                    // folder does not exist, so create it
                    createDocuments();
                } else {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultB1").text("Status: " + req.status + "\n\n" + text);
                }
            }
        });
        
        return false;
    });



    $("#formB2_update_options").click(function() {
        // update drop-down list of abstract csv folder names

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        $("#resultB2").empty();
        var fb='';
        $.ajax({
            type: 'GET',
            url: site.url + '/' + user_id + '/documents.json',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "json",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                data = $.parseJSON(req.responseText);
                if (data.folder != null) {
                    var folder_id = $("#abstracts_folder").val();
                    var options = '';
                    $.each(data.folder, 
                        function(i, item) {
                            options += '<option value="' + item.id + '"' +
                                       ((item.id == folder_id) ? ' selected="selected"' : '') +
                                       '>' + item.id + '</option>';
                        }
                    );
                    $('#abstract_documents').html(options);
                }
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultB2").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    });

    $("#formB2").submit(function() {
        
        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var folder_id = $("#abstract_documents").val();
        var profiles_url = site.url + '/' + user_id + '/profiles/' + folder_id;

        $("#resultB2").html('<br/><br/><em>Calculating profiles...</em>');

        var calculateProfile = function(folder_exists) {
            var mode = (($("#public_abstract_profiles:checked").val() === undefined) ? 'private' : 'public');
            $.ajax({
                type: (folder_exists) ? 'PUT' : 'POST',
                url: profiles_url + '/from/' + folder_id + '.json',
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'mode': mode,
                    'ngrams': '1,2,3',
                    'recalculate': '1'
                },
                dataType: "json",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    var isprivate = (mode === 'private') ? ' <em>(private)</em>' : '';
                    var s = '<br/>' +
                        '<blockquote>' +
                        '<h3 style="margin-top:0px;">Profiles Data: ' + folder_id + '</h3>' +
                        '<p>A profile has been calculated and, if required, can be accessed via the SubSift REST API and Linked Data.</p>' +
                        '<ul>' +
                        '<li><strong>Profile Items via SubSift API:</strong>' + isprivate +
                        '<ul>' +
                        '<li><a href="' + profiles_url + '/items.json?full=1" target="_new">JSON</a></li>' +
                        '<li><a href="' + profiles_url + '/items.terms?full=1" target="_new">Prolog Terms</a></li>' +
                        '<li><a href="' + profiles_url + '/items.rdf?full=1" target="_new">RDF</a></li>' +
                        '<li><a href="' + profiles_url + '/items.xml?full=1" target="_new">XML</a></li>' +
                        '<li><a href="' + profiles_url + '/items.yml?full=1" target="_new">YAML</a></li>' +
                        '</ul>' +
                        '</li>' +
                        '<li><strong>Profile Items via Linked Data:</strong>' + isprivate +
                        '<ul>' +
                        '<li><a href="' + profiles_url + '.rdf">' + profiles_url + '.rdf</a></li>' +
                        '</ul>' +
                        '</li>' +
                        '<ul>' +
                        '</blockquote>' +
                        '<p>If you wish to view, download or publish the profile as a report, proceed to Step 3.<br/>' + 
                        'Otherwise, go straight to Step 1 of "C. Profile Matcher" below.</p>';
                    $("#resultB2").html(s);
                    formC1_update_both();
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultB2").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };

        // check if folder already exists and then either create it or recalculate it
        $.ajax({
            type: 'HEAD',
            url: profiles_url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                calculateProfile(true);
            },
            error: function(req, textStatus, errorThrown) {
                if (req.status == 404) {
                    // folder does not exist, so create it
                    calculateProfile(false);
                } else {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultB2").text("Status: " + req.status + "\n\n" + text);
                }
            }
        });
        return false;
    });



    $("#formB3_update_options").click(function() {
        // update drop-down list of profiles folder names

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var fb='';
        $.ajax({
            type: 'GET',
            url: site.url + '/' + user_id + '/profiles.json',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "json",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                data = $.parseJSON(req.responseText);
                if (data.folder != null) {
                    var folder_id = $("#abstracts_folder").val();
                    var options = '';
                    $.each(data.folder, 
                        function(i, item) {
                            options += '<option value="' + item.id + '"' +
                                       ((item.id == folder_id) ? ' selected="selected"' : '') +
                                       '>' + item.id + '</option>';
                        }
                    );
                    $('#abstract_profiles').html(options);
                }
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultB3").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    });

    $("#formB3").submit(function() {
        // generate report from paper profiles

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var folder_id = $("#abstract_profiles").val();
        var reports_url = site.url + '/' + user_id + '/reports/' + folder_id;

        $("#resultB3").html('<br/><br/><em>Generating report...</em>');

        var calculateReports = function() {
            var mode = (($("#public_abstract_reports:checked").val() === undefined) ? 'private' : 'public');
            $.ajax({
                type: 'POST',
                url: reports_url + '/profiles/' + folder_id,
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'mode': mode,
                    'suppress_response_codes': '1'
                },
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    var isprivate = (mode === 'private') ? ' <em>(private)</em>' : '';
                    var s = '<br/>' +
                        '<blockquote>' +
                        '<h3 style="margin-top:0px;">Paper Profiles Report: ' + folder_id + '</h3>' +
                        '<p>A report has been generated and can be accessed at the following URLs.</p>' +
                        '<ul>' +
                        '<li><strong>Report Homepage:</strong>' + isprivate + '<br/>&nbsp; &nbsp;' +
                        '<a href="' + reports_url + '/" target="_new">' + reports_url + '/</a>' +
                        '</li>' +
                        '<li><strong>Report Download:</strong>' + isprivate + '<br/>&nbsp; &nbsp;' +
                        '<a href="' + reports_url + '.zip">' + reports_url + '.zip</a>' +
                        '</li>' +
                        '<ul>' +
                        '</blockquote>';
                    $("#resultB3").html(s);
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultB3").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };

        // delete any existing reports folder of this name before creating new one
        $.ajax({
            type: 'DELETE',
            url: reports_url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(data, textStatus, req) {
                // reports folder deleted, so go ahead and recreate
                calculateReports();
            },
            error: function(req, textStatus, errorThrown) {
                if (req.status == 404) {
                    // folder did not exist, so just go ahead and create
                    calculateReports();
                } else {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultB3").text("Status: " + req.status + "\n\n" + text);
                }
            }
        });

        return false;
    });



    //--------------------------------------------------------------------------------------------------
    // TABS C

    $("#tabsC").bind('tabsselect', function(event, ui) {
        if (ui.index === 0) {
            // load C.1 drop-down items if not already done so
            if ($('#match_abstract_profiles').val() == null) {
                formC1_update_both();
            }
        }
        else if (ui.index === 1) {
            // load C.2 drop-down items if not already done so
            if ($('#matches').val() == null) {
                $("#formC2_update_options").click();
            }
        }
    });


    var formC1_update_options = function(folder_id, selection_id) {
        // update drop-down lists of profiles folder names

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        $.ajax({
            type: 'GET',
            url: site.url + '/' + user_id + '/profiles.json',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "json",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                data = $.parseJSON(req.responseText);
                if (data.folder != null) {
                    var options = '';
                    $.each(data.folder, 
                        function(i, item) {
                            options += '<option value="' + item.id + '"' +
                                       ((item.id == folder_id) ? ' selected="selected"' : '') +
                                       '>' + item.id + '</option>';
                        }
                    );
                    $('#' + selection_id).html(options);
                }
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultC1").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    };
    var formC1_update_both = function() {
        formC1_update_options($("#reviewers_folder").val(), 'match_reviewer_profiles');
        formC1_update_options($("#abstracts_folder").val(), 'match_abstract_profiles');
    };
    $("#formC1_update_options1").click(formC1_update_both);
    $("#formC1_update_options2").click(formC1_update_both);


    $("#formC1").submit(function() {
        
        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var folder_id = $("#matches_folder").val();

        var folder_id1 = $("#match_reviewer_profiles").val();
        var folder_id2 = $("#match_abstract_profiles").val();
        if (folder_id1 == '' || folder_id2 == '') {
            alert('Please select a pair of profiles to compare.');
            formC1_update_both();
            return false;
        }
        var matches_url = site.url + '/' + user_id + '/matches/' + folder_id;

        $("#resultC1").html('<br/><br/><em>Calculating profiles...</em>');

        var calculateMatches = function(folder_exists) {
            var mode = (($("#public_matches:checked").val() === undefined) ? 'private' : 'public');
            $.ajax({
                type: (folder_exists) ? 'PUT' : 'POST',
                url: matches_url + '/profiles/' + folder_id1 + '/with/' + folder_id2 + '.json',
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'mode': mode,
                    'recalculate': '1',
                    'limit': 7,
                    'full': '0'
                },
                dataType: "json",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    var isprivate = (mode === 'private') ? ' <em>(private)</em>' : '';
                    var s = '<br/>' +
                        '<blockquote>' +
                        '<h3 style="margin-top:0px;">Profiles Data: ' + folder_id + '</h3>' +
                        '<p>Profile matches have been calculated and, if required, can be accessed via the SubSift REST API and Linked Data.</p>' +
                        '<ul>' +
                        '<li><strong>Match Items via SubSift API:</strong>' + isprivate +
                        '<ul>' +
                        '<li><a href="' + matches_url + '/items.json?full=1" target="_new">JSON</a></li>' +
                        '<li><a href="' + matches_url + '/items.terms?full=1" target="_new">Prolog Terms</a></li>' +
                        '<li><a href="' + matches_url + '/items.rdf?full=1" target="_new">RDF</a></li>' +
                        '<li><a href="' + matches_url + '/items.xml?full=1" target="_new">XML</a></li>' +
                        '<li><a href="' + matches_url + '/items.yml?full=1" target="_new">YAML</a></li>' +
                        '</ul>' +
                        '</li>' +
                        '<li><strong>Match Items via Linked Data:</strong>' + isprivate +
                        '<ul>' +
                        '<li><a href="' + matches_url + '.rdf">' + matches_url + '.rdf</a></li>' +
                        '</ul>' +
                        '</li>' +
                        '<ul>' +
                        '</blockquote>' +
                        '<p>If you wish to view, download or publish the matches as a report, proceed to Step 2.<br/>';
                    $("#resultC1").html(s);
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultC1").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };

        // check if folder already exists and then either create it or recalculate it
        $.ajax({
            type: 'HEAD',
            url: matches_url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                calculateMatches(true);
            },
            error: function(req, textStatus, errorThrown) {
                if (req.status == 404) {
                    // folder does not exist, so create it
                    calculateMatches(false);
                } else {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultC1").text("Status: " + req.status + "\n\n" + text);
                }
            }
        });
        return false;
    });


    $("#formC2_update_options").click(function() {
        // update drop-down list of documents folder names

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        $.ajax({
            type: 'GET',
            url: site.url + '/' + user_id + '/matches.json',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "json",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(rawdata, textStatus, req) {
                data = $.parseJSON(req.responseText);
                if (data.folder != null) {
                    var folder_id = $("#matches_folder").val();
                    var options = '';
                    $.each(data.folder, 
                        function(i, item) {
                            options += '<option value="' + item.id + '"' +
                                       ((item.id == folder_id) ? ' selected="selected"' : '') +
                                       '>' + item.id + '</option>';
                        }
                    );
                    $('#matches').html(options);
                }
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#resultC2").text("Status: " + req.status + "\n\n" + text);
            }
        });
        return false;
    });

    $("#formC2").submit(function() {
        // generate report from matches folder

        var user_id = $("#user_id").val();
        var token = $("#token").val();
        if (user_id == '' || token == '') {
            alert('Please enter a user_id and token into the form at the start of this page and then submit again.');
            return false;
        }

        var folder_id = $("#matches").val();
        var reports_url = site.url + '/' + user_id + '/reports/' + folder_id;

        $("#resultC2").html('<br/><br/><em>Generating report...</em>');

        var calculateReports = function() {
            var mode = (($("#public_matches_reports:checked").val() === undefined) ? 'private' : 'public');
            $.ajax({
                type: 'POST',
                url: reports_url + '/matches/' + folder_id,
                contentType: "application/x-www-form-urlencoded; charset=utf-8",
                data: {
                    'mode': mode,
                    'suppress_response_codes': '1'
                },
                dataType: "text",
                beforeSend: function (req) {
                    req.setRequestHeader("Token", token);
                },
                success: function(data, textStatus, req) {
                    var isprivate = (mode === 'private') ? ' <em>(private)</em>' : '';
                    var s = '<br/>' +
                        '<blockquote>' +
                        '<h3 style="margin-top:0px;">Matches Report: ' + folder_id + '</h3>' +
                        '<p>A report has been generated and can be accessed at the following URLs.</p>' +
                        '<ul>' +
                        '<li><strong>Matches Homepage:</strong>' + isprivate + '<br/>&nbsp; &nbsp;' +
                        '<a href="' + reports_url + '/" target="_new">' + reports_url + '/</a>' +
                        '</li>' +
                        '<li><strong>Matches Download:</strong>' + isprivate + '<br/>&nbsp; &nbsp;' +
                        '<a href="' + reports_url + '.zip">' + reports_url + '.zip</a>' +
                        '</li>' +
                        '<ul>' +
                        '</blockquote>';
                    $("#resultC2").html(s);
                },
                error: function(req, textStatus, errorThrown) {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultC2").text("Status: " + req.status + "\n\n" + text);
                }
            });
        };

        // delete any existing reports folder of this name before creating new one
        $.ajax({
            type: 'DELETE',
            url: reports_url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: null,
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token);
            },
            success: function(data, textStatus, req) {
                // reports folder deleted, so go ahead and recreate
                calculateReports();
            },
            error: function(req, textStatus, errorThrown) {
                if (req.status == 404) {
                    // folder did not exist, so just go ahead and create
                    calculateReports();
                } else {
                    var text = (req == null) ? '' : req.responseText;
                    $("#resultC2").text("Status: " + req.status + "\n\n" + text);
                }
            }
        });

        return false;
    });




});
