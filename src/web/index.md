{% extends "layout/base.html" %}
{% block title %}homepage{% endblock %}
{% block content -%}
## Dear [Delta Chat](https://get.delta.chat) users and newcomers...

Welcome to instant, interoperable and [privacy-preserving](/privacy) messaging :)

<a href="DCACCOUNT:https://{{ mail_domain }}/new" class="cta-button">
  Get a {{ mail_domain }} chat profile
</a>

If you are viewing this page on a different device
without a Delta Chat app,
you can also **scan this QR code** with Delta Chat:

<a href="DCACCOUNT:https://{{ mail_domain }}/new">
  <img width="300" style="float:none" src="qr-invite-{{ mail_domain }}.png">
</a>

🐣 **Choose** your Avatar and Name  
💬 **Start** chatting with any Delta Chat contacts using [QR invite codes](https://delta.chat/en/help#howtoe2ee)
{%- endblock %}
