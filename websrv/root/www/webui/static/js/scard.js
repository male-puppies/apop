$(function(){
	$("body").append('<div id="maskgray"></div><div id="sms"><div class="sms-top"><h2>短信验证</h2><a class="sms-close"></a></div><div class="sms-main"><p class="smswarn"></p><div><input id="smsPhone" type="text" placeholder="请输入手机号码" value="" /></div><div><input id="smsCaptcha" type="text" placeholder="请输入验证码" value="" /><button id="smsGetcap" class="getshover" onClick="getCap()">获取验证码</button></div><div><button id="smsSubmit" onClick="getSubmit()">确定</button><p id="get_warn"></p><p id="get_success"></p></div></div></div>');

	$("body").on("click", ".sms-close", function() {
		$("#maskgray,#sms").css("display","none");
	})
	
	$("body").on("focus", "#smsPhone", function() {
		$("p#get_warn").hide();
		$("p#get_success").hide();
		if($(this).hasClass("have")){
			$(".smswarn").html("");
			$(this).css("border","1px solid #ddd");
		}
		$(this).css("border","1px solid #488ee7");
	})
	$("body").on("blur", "#smsPhone", function() {
		$(this).css("border","1px solid #ddd");
		warnPhone();
	})
	
	$("body").on("focus", "#smsCaptcha", function() {
		$("p#get_warn").hide();
		$("p#get_success").hide();
		if($(this).hasClass("have")){
			$(".smswarn").html("");
			$(this).css("border","1px solid #ddd");
		}
		$(this).css("border","1px solid #488ee7");
	})
	$("body").on("blur", "#smsCaptcha", function() {
		$(this).css("border","1px solid #ddd");
	})

})

function showRecharge() {
	$("#smsCaptcha").val("");
	$("#get_warn, #get_success").hide();
	$("#maskgray, #sms").css("display", "block");
}

function timeWait(wait) {
	if (wait == 0) {
		$("#smsGetcap").attr("disabled", false);	
		$("#smsGetcap").html("获取验证码").removeClass("getsuccess").addClass("getshover");
		wait = 30;
	} else {
		$("#smsGetcap").attr("disabled", true);
		$("#smsGetcap").html('重新发送' + wait).removeClass("getshover").addClass("getsuccess");
		wait--;
		setTimeout(function() {
			timeWait(wait)
		},
		1000)
	}
}

function getCap(){
	var params = window.location.search;
	emptyPhone();
	warnPhone();
	var warn1 = emptyPhone();
	if(warn1 == false){return}
	var warn2 = warnPhone();
	if(warn2 == false){return}
	$.post(
		"/PhoneNo" + params,
		{
			"UserName" : $("#smsPhone").val()
		},
		function (d){
			if (d.status == 0) {
				timeWait(30);
				$("p#get_warn").hide();
				$("p#get_success").html("获取验证码成功！").show();
			} else {
				if (typeof d.data != "undefined") {
					$("p#get_success").hide();
					$("p#get_warn").html(d.data).show();
				} else {
					$("p#get_success").hide();
					$("p#get_warn").html("获取验证码失败！").show();
				}
			}
		},
		"json"
	)
}
function getSubmit(){
	var params = window.location.search;
	var warn1 = emptyPhone();
	if(warn1 == false){return}
	var warn2 = warnPhone();
	if(warn2 == false){return}
	var warn3 = emptyCap();
	if(warn3 == false){return}
	

	$.ajaxSetup ({
		cache: false //关闭AJAX相应的缓存
	});

	$.post(
		"../../cloudlogin" + params,
		{
			"UserName" : $("#smsPhone").val(),
			"Password" : $("#smsCaptcha").val()
		},
		function (d){
			if (d.status == 0) {
				if (d.data == "ok") {
					window.location.href = "http://www.baidu.com";
				} else {
					window.location.href = d.data;
				}
			} else {
				if (typeof d.data != "undefined") {
					$("p#get_success").hide();
					$("p#get_warn").html(d.data).show();
				} else {
					$("p#get_success").hide();
					$("p#get_warn").html("登录失败！").show();
				}
			}
		},
		"json"
	)
}

function emptyPhone(){
	var val = $("#smsPhone").val();
	if($.trim(val) == ''){
		$("#smsCaptcha").removeClass("have");
		$("#smsPhone").addClass("have");
		$("#smsPhone,#smsCaptcha").css("border","1px solid #ddd");
		$("#smsPhone").css("border","1px solid #F00");
		$(".smswarn").html("请填写手机号码");
		return false;
	}else{
		return true;
	}
}
function warnPhone(){
	var val = $("#smsPhone").val();
	var capPhone = /^1[3-8][0-9]\d{8}$/;
	if(!capPhone.test(val) && $.trim(val) != ''){
		$("#smsCaptcha").removeClass("have");
		$("#smsPhone").addClass("have");
		$("#smsPhone,#smsCaptcha").css("border","1px solid #ddd");
		$("#smsPhone").css("border","1px solid #F00");
		$(".smswarn").html("手机号码格式不正确");
		return false;
	}else{
		return true;
	}
}
function emptyCap(){
	var val = $("#smsCaptcha").val();
	if($.trim(val) == ''){
		$("#smsPhone").removeClass("have");
		$("#smsCaptcha").addClass("have");
		$("#smsPhone,#smsCaptcha").css("border","1px solid #ddd");
		$("#smsCaptcha").css("border","1px solid #F00");
		$(".smswarn").html("请填写验证码");
		return false;
	}else{
		return true
	}
}
/*function warnCap(){
	var val = $("#smsCaptcha").val();
	if(val){
		$(".smswarn").html("验证码不存在或已过期,请重新输入")
	}
}*/