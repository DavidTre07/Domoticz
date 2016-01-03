--[[
  David Tre (david.tre07@gmail.com)
  29/12/2015
  Script developped after this wiki page was not working anymore https://www.domoticz.com/wiki/Interacting_with_Google_Calendar
  
  Before putting this script in the domoticz scripts folder take care that:
    - gcalcli is installed and configured
    - put a cron like this */10 * * * * /usr/local/bin/gcalcli agenda yesterday tomorrow --calendar Domoticz --military --tsv >/var/tmp/gcalcli.txt
  Verify that you got a new /var/tmp/gcalcli.txt file every 10 minutes
  If yes you are ready to go! (put this script in ~/domoticz/scripts/lua/script_time_calendar_oauth2.lua)
  
  03/01/2015: Added the possibility to put multiple actions in one schedule, each command separated with a semicolon: Device1=On;Device2==On;User_Var3=1"
--]]

-- VARIABLES
id ="(CAL) "   -- Prefix to put on each messages
debug = false   -- Debug mode: debug= true|false
LUAevents = true   -- Do we accept LUA code in the calendar ? LUAevents= true|false
tmpdir = "/var/tmp/"   -- Where to put the temporary files
calendarFilename="gcalcli.txt"   -- Where the cron put the calendar entries
scriptFilename="loadstring.tmp"   -- Where to store the script before running it
lang="fr"   -- Choose your language for the time being: lang= "en"|"fr"
-- END of VARIABLES

-- MESSAGES
messages={}   -- messages table initialisation
messages["en"]={}   -- en lang initialisation
messages["fr"]={}   -- fr lang initialisation
messages["en"]["Can't open"]="Can't open"
messages["fr"]["Can't open"]="Impossible d'ouvrir"
messages["en"]["f() returns"]="f() returns"
messages["fr"]["f() returns"]="f() renvoie"
messages["en"]["Error"]="Error"
messages["fr"]["Error"]="Erreur"
messages["en"]["Processing"]="Processing"
messages["fr"]["Processing"]="Traitement"
messages["en"]["ERROR, This device or user variable doesn't exist"]="ERROR, This device or user variable doesn't exist"
messages["fr"]["ERROR, This device or user variable doesn't exist"]="ERREUR, Ce périphérique ou cette variable n'existe pas"
messages["en"]["ERROR, I can not understand this action"]="ERROR, I can not understand this action"
messages["fr"]["ERROR, I can not understand this action"]="ERREUR, Je ne comprends pas cette action"
messages["en"]["Not in the time slot"]="Not in the time slot"
messages["fr"]["Not in the time slot"]="Pas dans le créneau de temps"
messages["en"]["Only found a comment in the action field"]="Only found a comment in the action field..."
messages["fr"]["Only found a comment in the action field"]="Seulement trouvé un commentaire dans le champ action..."
messages["en"]["Can't open Calendar file"]="Can't open calendar file"
messages["fr"]["Can't open Calendar file"]="Impossible d'ouvrir le fichier du calendrier"
messages["en"]["Script to run"]="Script to run"
messages["fr"]["Script to run"]="Script a exécuter"
-- END of MESSAGES

printf = function(s,...) return print(id..s:format(...)) end   -- Prefix all print with the var: id
 
function loadstring(str,name) -- Omit this function if your domoticz supports it natively
  local file = tmpdir..scriptFilename
  local f,err=io.open(file,"w")
  if not f then
    printf("%s: %s (%s)",messages[lang]["Can't open"],file,err)
  else
    f:write(str)
    f:close()
    f,err=loadfile(file)
    if f then f,err=f() 
      if debug then printf('%s %s (%s)',messages[lang]["f() returns"],f,err) end
    end
  end
  return f,err
end
 
commandArray = {}
 
currentTime=tonumber(os.date("%Y%m%d%H%M")) -- yyyymmddhhmm format
--printf('%s',currentTime)
 
--Lines format: StartDate  StartTime  EndDate  EndTime  Event
-- Example: 2015-12-28  09:00  2015-12-28  13:00  VMC=off
calendarFile=tmpdir..calendarFilename fhnd,err=io.open(calendarFile)
if fhnd then
  for line in fhnd:lines() do
    if debug then printf("%s",line) end
    eventStartDate, eventStartHour, eventEndDate, eventEndHour, eventActionFull=line:match("([^,]+)\t([^,]+)\t([^,]+)\t([^,]+)\t([^,]+)")  -- We have only 5 fields !
    eventStart=tonumber(string.gsub(eventStartDate,"-","")..string.gsub(eventStartHour,":",""))   -- Remove separators in date and time
    eventEnd=tonumber(string.gsub(eventEndDate,"-","")..string.gsub(eventEndHour,":",""))   -- Join date and time for comparisons
    
    spos,epos=string.find(eventActionFull,"%-%-")   -- Find if the action field is only a comment (starting with --)
    if(spos~=1) then   -- If the action don't start with a comment we can process action field
      if (currentTime>=eventStart and (currentTime<=eventEnd or eventStart>eventEnd)) then  -- Are we in the time slot ?
        eventAction=eventActionFull:match("([^--]+)--")   -- Remove comments in action field
        if debug then printf("%s --> currentTime: %s eventStart: %s eventEnd: %s Action: %s",messages[lang]["Processing"],currentTime,eventStart,eventEnd,eventAction) end
        if LUAevents and (eventAction:find("%(") or eventAction:find("%[")) then -- Non-trivial LUA code
          -- Translations
          eventScript = eventAction:gsub(";",",") -- Subst the "," character
          eventScript = eventScript:gsub("cA","commandArray")
          eventScript = eventScript:gsub("odsval","otherdevices_svalues")
          eventScript = eventScript:gsub("odhum","otherdevices_humidity")
          eventScript = eventScript:gsub("odtemp","otherdevices_temperature")
          eventScript = eventScript:gsub("od","otherdevices")
          -- End of Translations
          if debug then printf("%s: %s",messages[lang]["Script to run"],eventScript) end
          sts,err = loadstring(eventScript)   -- Run the script
          if err ~= nil then   -- Error return ?
            printf("%s: %s",messages[lang]["Error"],err)
          end
        else   -- We are not in the case of a LUA code
          _trash,numberOfEqual=eventAction:gsub("(=)","%1")   -- In the action we have a = ?
          if (numberOfEqual~=0) then   -- OK we found at least one =
            for device,newSetting in string.gmatch(eventAction,"([^;]+)[==|=]([^;]+)") do
              forceAction=false
              device,nbEqual=device:gsub("(=)","")
              if(nbEqual~=0) then forceAction=true end   -- Remaining a = in device name ? then we are in force mode
              if (otherdevices[device]~= nil) then   -- Is the device exist ?
                if forceAction or (otherdevices[device] ~= newSetting) then   -- if == (force state) or device not on the requested state
                  commandArray[device]=newSetting   -- OK we apply the new command
                end
              else   -- No the device doesn't exist
                if (uservariables[device]~= nill) then   -- Is a user variable with this name exist ?
                  if (type(uservariables[device])=="number") then actualSetting=tostring(uservariables[device]) else actualSetting=uservariables[device] end
                  if (actualSetting~=newSetting) then commandArray['Variable:'..device]=newSetting end
                else
                  printf("%s %s",messages[lang]["ERROR, This device or user variable doesn't exist"],device)
                end
              end
            end
          else   -- No = sign, strange...
            printf("%s: %s",messages[lang]["ERROR, I can not understand this action"],eventAction)
          end
        end
      else
        if debug then printf("%s",messages[lang]["Not in the time slot"]) end
      end
    else
      if debug then printf("%s",messages[lang]["Only found a comment in the action field"]) end
    end
  end
  fhnd:close()
else
  printf("%s: %s (%s)",messages[lang]["Can't open Calendar file"],calendarFile,err)
end
 
for i,v in pairs(commandArray) do printf("commandArray[%q] =  %q",i,v) end
 
return commandArray
