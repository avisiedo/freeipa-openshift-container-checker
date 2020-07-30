<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:template match="/">
<xsl:for-each select="html/body/div[@class='container']/table/tbody/tr/td/i/a"><xsl:value-of select="@href"/><xsl:text>&#x0A;</xsl:text>
</xsl:for-each>
</xsl:template>

</xsl:stylesheet>