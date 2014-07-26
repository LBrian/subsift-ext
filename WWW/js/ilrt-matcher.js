function token() { return "26c39c8e44bf9990c2a0c02b1353f376c588a9c3"; }

function formatNumber(n, dp) {
    var s = '' + (Math.round(n * Math.pow(10, dp)) / Math.pow(10, dp));
    var p = s.indexOf('.');
    var rhs, lhs;
    if (p >= 0) {
        rhs = s.substr(p+1);
        s = s.substr(0, p+1);
    } else {
        rhs = '';
        s += '.';
    }
    while(rhs.length < dp) {
        rhs += '0';
    }
    return s + rhs;
}

function bar_chart(summary, title, xlabel, ylabel, data, params) {

    var maxwidth = 580;  // requested maximum chart width for x axis
    var gridwidth = 58;  // width of vertical grid bar graphic (a line and lots of transparent white space)
    maxwidth = Math.floor((maxwidth + gridwidth-1) / gridwidth) * gridwidth; //ensure exact multiple of grid width

    var maxval = (params.autoscale) ? 1 * data[0].value : 1;

    var str = 
        '<table cellspacing="0" cellpadding="0" summary="' + summary + '">' + 
          '<caption align="top">' + title + '<br /><br /></caption>' + 
          '<tr>' + 
            '<th scope="col" width="180"><span class="auraltext">' + ylabel + '</span> </th>' + 
            '<th scope="col" width="' + (maxwidth + gridwidth - 10) + '"><span class="auraltext">' + xlabel + '</span> </th>' + 
          '</tr>';

    for(var i=0; i<data.length; i++) {
        var item = data[i];

        var is_first = (i === 0) ? true : false;
        var is_last = (i === (data.length - 1)) ? true : false;

        var width = Math.round(item.value * maxwidth / maxval);

        var val = '';
        if (params.show_values) {
            val += formatNumber(item.value, 3);
        }
        if (params.show_terms) {
            val += '<br/><div class="terms">' + item.terms + '</div>';
        }

        str +=
          '<tr>' + 
            '<td' + ((is_first) ? ' class="first"' : '') + '><a href="' + item.url + '" target="_new' + i + '" class="external">' + item.label + '</a></td>' + 
            '<td class="value' + 
                ((is_first) ? ' first' : '') + 
                ((is_last)  ? ' last' : '') + 
                '"><img src="' + site.media + '/img/demo/bar.png" alt="" width="' + width + '" height="16" />' + val + 
                '</td>' + 
          '</tr>';
    }

    str +=  
        '</table>';

    return str;
}

function displayRanking(url) {
    $("#result").text("Drawing Similarity Chart...");
    $.ajax({
        type: 'GET',
        url: url + '/ilrt/matches/abstract_staff/items/abstract.json?full=1', 
        contentType: "application/x-www-form-urlencoded; charset=utf-8",
        data: {
        },
        dataType: "json",
        beforeSend: function (req) {
            req.setRequestHeader("Token", token());
        },
        success: function(rawdata, textStatus, req) {
            data = $.parseJSON(req.responseText);
/* This method exceeds HTTP GET size restriction on Google's charts api (would have to use POST, which requires cross-site hack)
            var s = "";
            var x = "";
            var y = "";
            var n = 0;
            $.each(data.match.item, 
                function(i, item) {
                     s = s + item["name"] + " - " + item["score"] + "\n";
                     x = x + item[1]*2 + ",";
                     y = "|" + encodeURI(item["name"]) + y;
                     n++;
                     if (n > 5) { break; }
                }
            );
//            $("#result").text(s);
            // google chart
            x = x.substring(0, x.length-1);
            y = y + "|";
            var wid = 800;
            var hgt = 60 * n;
            var charturl = "http://chart.apis.google.com/chart?" +
                "&chs=" + wid + "x" + hgt + 
                "&cht=bhs" +
                //"&chco=D11D6D" +
                "&chco=4060F0" +
                "&chxt=x,x,y" +
                "&chd=t:" + x +
                "&chds=0,1" +
                "&chxr=0,0,1,0.1" +
                "&chtt=ILRT+staff+ranked+by+similarity+to+text" +
                "&chts=222222,20" +
                "&chxp=1:50" +
                "&chxl=1:||similarity||" +
                      "2:" + y
                      
            ;
            $("#result").html(
                '<img src="' + charturl  + '" width="' + wid + '" height="' + hgt + '"></img>'
            );
*/
            var autoscale = ($("#id-autoscale:checked").val() === undefined) ? false : true;
            var show_values = ($("#id-show_values:checked").val() === undefined) ? false : true;
            var show_terms = ($("#id-show_terms:checked").val() === undefined) ? false : true;

            var plotdata = [];
            $.each(data.match.item, 
                function(i, item) {
                    var total = 0;
                    $.each(item.term,
                        function(j, term) {
                            total = total + (1.0 * term.contribution);
                        }
                    );
                    var termstr = '';
                    $.each(item.term,
                        function(j, term) {
                            var contrib = formatNumber(term.contribution * 100 / total, 2);
                            termstr += ((termstr == '') ?'' : ', ') + term.name;
                            if (show_values) {
                                termstr += '&nbsp;(' + contrib + '%)';
                            }
                        }
                    );
                    if (termstr == '') { termstr = '<em>none</em>';  }
                    plotdata.push({"label": item["description"], "value": item["score"], "url": item["source"], "terms": termstr});
                }
            );
            $("#result").html(
                bar_chart(
                    '', 
                    'ILRT staff ranked by similarity to text',
                    'Staff Member',
                    'Similarity',
                    plotdata,
                    {
                        'autoscale': autoscale,
                        'show_values': show_values,
                        'show_terms': show_terms
                    }
                )
            );

        },
        error: function(req, textStatus, errorThrown) {
            var text = (req == null) ? '' : req.responseText;
            $("#result").text("Status: " + req.status + "\n\n" + text);
        }
    });
}


function generateProfile(url) {
    $("#result").text("Calculating Profile...");
    $.ajax({
        type: 'POST',
        url: url + '/ilrt/profiles/abstract/recalculate',
        contentType: "application/x-www-form-urlencoded; charset=utf-8",
        data: {
        },
        dataType: "text",
        beforeSend: function (req) {
            req.setRequestHeader("Token", token());
        },
        success: function(data, textStatus, req) {
            matchProfiles(url);
        },
        error: function(req, textStatus, errorThrown) {
            var text = (req == null) ? '' : req.responseText;
            $("#result").text("Status: " + req.status + "\n\n" + text);
        }
    });
}

function matchProfiles(url) {
    $("#result").text("Matching Profiles...");
    $.ajax({
        type: 'POST',
        url: url + '/ilrt/matches/abstract_staff/recalculate',
        contentType: "application/x-www-form-urlencoded; charset=utf-8",
        data: {
        },
        dataType: "text",
        beforeSend: function (req) {
            req.setRequestHeader("Token", token());
        },
        success: function(data, textStatus, req) {
            displayRanking(url);
        },
        error: function(req, textStatus, errorThrown) {
            var text = (req == null) ? '' : req.responseText;
            $("#result").text("Status: " + req.status + "\n\n" + text);
        }
    });
}


$(function() {
    
    $("#demoform").submit(function() {
        
        $("#result").empty();

        // store the submitted text as a document item
        var text = $("#text").val();
        var url = $("#url").val();
        if (text == '') {
            alert("Enter some text before submitting.");
            return false;
        }
        $.ajax({
            type: 'PUT',
            url: url + '/ilrt/documents/abstract/items/abstract',
            contentType: "application/x-www-form-urlencoded; charset=utf-8",
            data: {
                'text': text,
                'description': 'text submitted via demo form'
            },
            dataType: "text",
            beforeSend: function (req) {
                req.setRequestHeader("Token", token());
            },
            success: function(data, textStatus, req) {
                generateProfile(url);
            },
            error: function(req, textStatus, errorThrown) {
                var text = (req == null) ? '' : req.responseText;
                $("#result").text("Status: " + req.status + "\n\n" + text);
            }
        });

        return false;
    });    

});

