
$(function() {
    
    $("#demoform").submit(function() {
        
//        var method = $("input[name=method]:checked").val();
        var method = $("select[name=method]").val();
        var url = site.url + encodeURI(decodeURI( $("#url").val() ));

        var token = $("#token").val();
        
        $('#current-query').empty();
        $("#result").empty();

        var fields = $("#demoform").serializeArray();
        var params = {};
        var qstr = '';
        var args = '';
        var nm = undefined;
        jQuery.each(fields, function(i, field){
            if (field.name == 'name') {
                nm = field.value;
            } else {
                if (field.name == 'value' && nm != undefined && nm.length > 0) {
                    params[nm] = field.value;
                    args += nm + '=' + field.value.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') + '<br/>';
                }
                nm = undefined;
            }
        });

        if (method == 'HEAD' || method == 'GET') {
            // head parameters must be sent in query string of the url
            var queryStr = $.param(params);
            if (queryStr != '') {
                url += ((url.indexOf('?') < 0) ? '?' : '&') + queryStr;
            }
            params = {};
            args = '';
        }

        $('#current-query').append(method + ' - ' + url + '<br/>' + args);
        $("#result").text('Loading...');

        $.ajax({
            type: method,
            url: url,
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
//            contentType: "multipart/form-data; charset=utf-8",
            data: params,
            dataType: "text", //"script",
            beforeSend: function (req)
            {
                req.setRequestHeader("Token", token);
            },
            success: function(data, textStatus, req) {
                var text = (req == null) ? '' : req.responseText;
//                var result = text.match(/<html[^>]*>.*<body[^>]*>(.*)<\/body>/i);
                if (text.indexOf('<html') >= 0) {
//                if (result !== null) {
//                    $("#result").html(result[1]);
                    $("#result").html(text);
                } else {
                    $("#result").text("Status: " + req.status + "\n\n" + text);
                }
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#result").text("Status: " + req.status + "\n\n" + text);
            }
        });

        return false;
    });
    
    // repeating parameter row in demo form
    $("#add_row_button").click(function() {
  
        $(".row:last").after( $(".row:last").clone() );
        var rowcnt = $(".row").length;

        $(".row:last > .name_label").text("Name " + rowcnt + ":");
        $(".row:last > .name").attr("id", "name_" + rowcnt);
        $(".row:last > .name_label").attr("for", "name_" + rowcnt);
        $(".row:last > .name").val("");

        $(".row:last > .value_label").text("Value " + rowcnt + ":");
        $(".row:last > .value").attr("id", "value_" + rowcnt);
        $(".row:last > .value_label").attr("for", "value_" + rowcnt);
        $(".row:last > .value").val("");

        $("#name_"+rowcnt).focus();

        return false;
    });

});

