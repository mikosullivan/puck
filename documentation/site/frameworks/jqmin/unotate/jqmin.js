$(document).ready(function(){
	// initialize radio buttons that can be unchecked
	$('input[type=radio].can-uncheck').each(function(){
		$(this).data('prev_checked', this.checked);
	});
	
	// handle radio buttons that can be unchecked
	$('input[type=radio].can-uncheck').click(function(e){
		this.checked = ! $(this).data('prev_checked');
		checked = this.checked
		
		// set prev_checked value for all radio buttons with this name
		if (this.name) {
			$('input[name="' + this.name + '"].can-uncheck').each(function(){
				$(this).data('prev_checked', this.checked);
			});
		}
		
		// fire change event
		$(this).change();
	});
	
	// checkbox that shadows the checkedness of another checkbox
	$('input[type=checkbox][id], input[type=radio][id]').change(function(e){
		set_shadows(this);
	});
	
	// checkbox that shadows the checkedness of another checkbox
	/*
	$('input[type=radio][id][name]').change(function(e){
		name = this['name'];
		src = this;
		
		// loop through sibling fields
		$(this).closest('form, body').each(function(){
			$(this).find('input[type=radio][name=' + name + ']').each(function(){
				
			});
		});
	});
	*/
	
	// form that hides when it is submited
	$('form.hide-on-submit').submit(function(e){
		$(this).hide();
	});
	
	// self-set
	$('img[data-self-set]').click(function(e){
		$(this).attr( 'src', $(this).attr('data-self-set') );
	});
	
	// submit-on-set: checkbox
	$('input[type=checkbox].submit-on-set').click(function(e){
		submit_on_set(this);
	});
	
	// submit-on-set: radio
	$('input[type=radio].submit-on-set').click(function(e){
		submit_on_set(this);
	});
	
	// submit-on-set: select
	$('select.submit-on-set').change(function(e){
		submit_on_set(this);
	});
	
	// popup
	$('a.popup').click(function(e){
		url = $(this).attr('href');
		
		// params
		params = {}
		params['scrollbars'] = $(this).attr('data-scrollbars') || 'no';
		params['resizable'] = $(this).attr('data-resizable') || 'no';
		params['status'] = $(this).attr('data-status') || 'no';
		params['location'] = $(this).attr('data-location') || 'no';
		params['toolbar'] = $(this).attr('data-toolbar') || 'no';
		params['menubar'] = $(this).attr('menubar') || 'no';
		params['width'] = $(this).attr('width') || 620;
		params['height'] = $(this).attr('width') || 320;
		
		// param string
		paramsStr = '';
		
		// build params string
		Object.keys(params).forEach(function (key) { 
			if (paramsStr.length > 0)
				paramsStr += ',';
			paramsStr += key + '=' + params[key];
		});
		
		window.open(url, 'test', paramsStr);
		return false;
	});
});

// submit_on_set
function submit_on_set(field){
	// if this field is in a form, submit that form
	if (field.form) {
		field.form.submit();
		return;
	}
	
	// get form attribute
	form_id = field.getAttribute('form');
	
	// else if form attribute, submit that form
	if (form_id) {
		$('#' + form_id).each(function(){
			this.submit();
			return false;
		});
	}
}

// set shadows for checkboxes and radios
function set_shadows(src){
	checked = src.checked;
	
	$('input[data-shadow=' + src.id + ']').each(function(){
		this.checked = checked
	});
}

/*
 * The following code is copied from Ben Alman's excellent outside events
 * jQuery plugin.
 * 
 * jQuery outside events - v1.1 - 3/16/2010
 * http://benalman.com/projects/jquery-outside-events-plugin/
 * 
 * Copyright (c) 2010 "Cowboy" Ben Alman
 * Dual licensed under the MIT and GPL licenses.
 * http://benalman.com/about/license/
 */
(function($,c,b){
$.map("click dblclick mousemove mousedown mouseup mouseover mouseout change select submit keydown keypress keyup".split(" "),
function(d){a(d)});
a("focusin","focus"+b);
a("focusout","blur"+b);
$.addOutsideEvent=a;
function a(g,e){e=e||g+b;
var d=$(),h=g+"."+e+"-special-event";
$.event.special[e]={setup:function(){d=d.add(this);
if(d.length===1){$(c).bind(h,f)}},teardown:function(){d=d.not(this);
if(d.length===0){$(c).unbind(h)}},add:function(i){var j=i.handler;
i.handler=function(l,k){l.target=k;
j.apply(this,arguments)}}};
function f(i){$(d).each(function(){var j=$(this);
if(this!==i.target&&!j.has(i.target).length){j.triggerHandler(e,[i.target])}})}}})(jQuery,document,"outside");
