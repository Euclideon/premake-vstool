
	local p = premake

	local sln2005 = p.vstudio.sln2005
	local vc2010 = p.vstudio.vc2010
	local vstudio = p.vstudio
	local project = p.project
	local config = p.config


--
-- always include _preload so that the module works even when not embedded.
--
	if premake.extensions == nil or premake.extensions.vstool == nil then
		include ( "_preload.lua" )
	end


--
-- Create an vstool namespace to isolate the additions
--
	p.modules.vstool = {}

	local m = p.modules.vstool
	m._VERSION = "0.0.1"


--
-- Helpers to see if we're dealing with a vs-tool action.
--

	function m.isgcc(cfg)
		return cfg.toolset == "gcc"
	end

	function m.isclang(cfg)
		return cfg.toolset == "clang"
	end

	function m.isgccorclang(cfg)
		return m.isgcc(cfg) or m.isclang(cfg)
	end

	function m.isvstool(cfg)
		return _ACTION:startswith("vs") and m.isgccorclang(cfg)
	end


--
-- Add vs-tool tools to vstudio actions.
--

	if vstudio.vs2010_architectures ~= nil then
		vstudio.vs2010_architectures.clang = "Clang"
		vstudio.vs2010_architectures.mingw = "MinGW"
	end

	premake.override(vstudio, "archFromConfig", function(oldfn, cfg, win32)
		if _ACTION:startswith("vs") then
			if cfg.toolset == "gcc" then
				return "MinGW"
			elseif cfg.toolset == "clang" then
				return "Clang"
			end
		end
		return oldfn(cfg, win32)
	end)


--
-- Extend configurationProperties.
--

	premake.override(vc2010, "platformToolset", function(orig, cfg)
		if m.isvstool(cfg) then
			-- is there a reason to write this? default is fine.
--			local map = { gcc="mingw", clang="clang" }
--			_p(2,'<PlatformToolset>%s</PlatformToolset>', map[cfg.toolset])
		else
			orig(cfg)
		end
	end)

	premake.override(vc2010, "configurationType", function(oldfn, cfg)
		if m.isvstool(cfg) then
			if cfg.kind then
				local types = {
					SharedLib = "DynamicLibrary",
					StaticLib = "StaticLibrary",
					ConsoleApp = "Application",
					WindowedApp = "Application",
				}
				local type = types[cfg.kind]
				if not type then
					error("Invalid 'kind' for vs-tool: " .. cfg.kind, 2)
				else
					if m.isclang(cfg) and cfg.kind == "StaticLib" then
						-- clang has some options...
						if cfg.flags.OutputBC then
							type = "StaticLibraryBc"
						else
							local libFormat = { [".o"]="StaticLibrary", [".a"]="StaticLibraryA", [".lib"]="StaticLibraryLib" }
							type = libFormat[cfg.staticlibformat or ".lib"]
						end
					end
					_p(2,'<ConfigurationType>%s</ConfigurationType>', type)
				end
			end
		else
			oldfn(cfg)
		end
	end)


--
-- Extend outputProperties.
--

	premake.override(vc2010.elements, "outputProperties", function(oldfn, cfg)
		local elements = oldfn(cfg)
		if cfg.kind ~= p.UTILITY then
			if m.isclang(cfg) then
				elements = table.join(elements, {
					m.clangPath,
				})
			elseif m.isgcc(cfg) then
				elements = table.join(elements, {
					m.mingwPath,
				})
			end
		end
		return elements
	end)

	function m.clangPath(cfg)
		if cfg.clangpath ~= nil then
--			local dirs = project.getrelative(cfg.project, includedirs)
--			dirs = path.translate(table.concat(fatalwarnings, ";"))
			_p(2,'<ClangPath>%s</ClangPath>', cfg.clangpath)
		end
	end

	function m.mingwPath(cfg)
		if cfg.mingwpath ~= nil then
--			local dirs = project.getrelative(cfg.project, includedirs)
--			dirs = path.translate(table.concat(fatalwarnings, ";"))
			_p(2,'<MinGWPath>%s</MinGWPath>', cfg.mingwpath)
		end
	end

	premake.override(vc2010, "targetExt", function(oldfn, cfg)
		if m.isgccorclang(cfg) then
			local ext = cfg.buildtarget.extension
			if ext ~= "" then
				_x(2,'<TargetExt>%s</TargetExt>', ext)
			end
		else
			oldfn(cfg)
		end
	end)


--
-- Extend clCompile.
--

	premake.override(vc2010.elements, "clCompile", function(oldfn, cfg)
		local elements = oldfn(cfg)
		if m.isvstool(cfg) then
			elements = table.join(elements, {
				m.debugInformation,
				m.enableWarnings,
				m.languageStandard,
				m.generateLlvmBc,
				m.targetArch,
				m.instructionSet,
			})
		end
		return elements
	end)

	function m.debugInformation(cfg)
		-- TODO: support these
		--     NoDebugInfo
		--     LimitedDebugInfo
		--     FullDebugInfo
		_p(3,'<GenerateDebugInformation>%s</GenerateDebugInformation>', iif(cfg.flags.Symbols, "FullDebugInfo", "NoDebugInfo"))
	end

	function m.enableWarnings(cfg)
		if #cfg.enablewarnings > 0 then
			_x(3,'<EnableWarnings>%s</EnableWarnings>', table.concat(cfg.enablewarnings, ";"))
		end
	end

	function m.languageStandard(cfg)
		local map = {
			c90         = "LanguageStandardC89",
			gnu90       = "LanguageStandardGnu89",
			c94         = "LanguageStandardC94",
			c99         = "LanguageStandardC99",
			gnu99       = "LanguageStandardGnu99",
--			["c++98"]   = "LanguageStandardCxx03",
--			["gnu++98"] = "LanguageStandardGnu++98",
--			["c++11"]   = "LanguageStandardC++11",
--			["gnu++11"] = "LanguageStandardGnu++11"
		}
		if cfg.languagestandard and map[cfg.languagestandard] then
			_p(3,'<LanguageStandardMode>%s</LanguageStandardMode>', map[cfg.languagestandard])
		end
	end

	function m.generateLlvmBc(cfg)
		if m.isclang(cfg) then
			if cfg.flags.OutputBC then
				_p(3,'<GenerateLLVMByteCode>true</GenerateLLVMByteCode>')
			end
		end
	end

	function m.targetArch(cfg)
		if m.isvstool(cfg) then
			if cfg.architecture == "x86" then
				_p(3,'<TargetArchitecture>x86</TargetArchitecture>')
			elseif cfg.architecture == "x86_64" then
				_p(3,'<TargetArchitecture>x64</TargetArchitecture>')
			elseif cfg.architecture then
				error("Invalid 'architecture' for vs-tool: " .. cfg.architecture, 2)
			end
		end
	end

	function m.instructionSet(cfg)
		if m.isvstool(cfg) then
			local map = {
				MMX="MMX",
				SSE="SSE",
				SSE2="SSE2",
				SSE3="SSE3",
				SSSE3="SSSE3",
				SSE4="SSE4",
				["SSE4.1"]="SSE4.1",
				["SSE4.2"]="SSE4.2",
				AVX="AVX",
				AVX2="AVX2",
			}
			if map[cfg.vectorextensions] ~= nil then
				_p(3,'<InstructionSet>%s</InstructionSet>', map[cfg.vectorextensions])
			end
		end
	end

	premake.override(vc2010, "disableSpecificWarnings", function(oldfn, cfg)
		if m.isvstool(cfg) then
			if #cfg.disablewarnings > 0 then
				local warnings = table.concat(cfg.disablewarnings, ";")
				warnings = premake.esc(warnings) .. ";%%(DisableWarnings)"
				vc2010.element('DisableWarnings', condition, warnings)
			end
		else
			oldfn(cfg)
		end
	end)

	premake.override(vc2010, "treatSpecificWarningsAsErrors", function(oldfn, cfg)
		if m.isvstool(cfg) then
			if #cfg.fatalwarnings > 0 then
				local fatal = table.concat(cfg.fatalwarnings, ";")
				fatal = premake.esc(fatal) .. ";%%(SpecificWarningsAsErrors)"
				vc2010.element('SpecificWarningsAsErrors', condition, fatal)
			end
		else
			oldfn(cfg)
		end
	end)

	premake.override(vc2010, "undefinePreprocessorDefinitions", function(oldfn, cfg, undefines, escapeQuotes, condition)
		if m.isvstool(cfg) then
			if #undefines > 0 then
				undefines = table.concat(undefines, ";")
				if escapeQuotes then
					undefines = undefines:gsub('"', '\\"')
				end
				undefines = premake.esc(undefines) .. ";%%(PreprocessorUndefinitions)"
				vc2010.element('PreprocessorUndefinitions', condition, undefines)
			end
		else
			oldfn(cfg, undefines, escapeQuotes, condition)
		end
	end)

	premake.override(vc2010, "warningLevel", function(oldfn, cfg)
		if m.isgccorclang(cfg) then
			local map = { Off = "DisableAllWarnings", Extra = "AllWarnings" }
			if map[cfg.warnings] ~= nil then
				_p(3,'<Warnings>%s</Warnings>', map[cfg.warnings])
			end
		else
			oldfn(cfg)
		end
	end)

	premake.override(vc2010, "treatWarningAsError", function(oldfn, cfg)
		if m.isgccorclang(cfg) then
			if cfg.flags.FatalCompileWarnings and cfg.warnings ~= premake.OFF then
				_p(3,'<WarningsAsErrors>true</WarningsAsErrors>')
			end
		else
			oldfn(cfg)
		end
	end)

	premake.override(vc2010, "optimization", function(oldfn, cfg, condition)
		if m.isgccorclang(cfg) then
			local map = { Off="O0", On="O2", Debug="O0", Full="O3", Size="Os", Speed="O3" }
			local value = map[cfg.optimize]
			if value or not condition then
				value = value or "O0"
				if m.isclang(cfg) and cfg.flags.LinkTimeOptimization and value ~= "O0" then
					value = "O4"
				end
				vc2010.element('OptimizationLevel', condition, value)
			end
		else
			oldfn(cfg, condition)
		end
	end)

	premake.override(vc2010, "exceptionHandling", function(oldfn, cfg)
		-- ignored for vs-tool
		if not m.isvstool(cfg) then
			oldfn(cfg)
		end
	end)

	premake.override(vc2010, "additionalCompileOptions", function(oldfn, cfg, condition)
		if m.isvstool(cfg) then
			m.additionalOptions(cfg, condition)
		end
		return oldfn(cfg, condition)
	end)

	-- these should be silenced for vs-tool based toolsets
	premake.override(vc2010, "debugInformationFormat", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)
	premake.override(vc2010, "functionLevelLinking", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)
	premake.override(vc2010, "intrinsicFunctions", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)
	premake.override(vc2010, "minimalRebuild", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)
	premake.override(vc2010, "omitFramePointers", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)
	premake.override(vc2010, "stringPooling", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)
	premake.override(vc2010, "runtimeLibrary", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)
	premake.override(vc2010, "bufferSecurityCheck", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)


--
-- Extend Link.
--

	premake.override(vc2010, "generateDebugInformation", function(oldfn, cfg)
		-- Note: vs-tool specifies the debug info in the clCompile section
		if not m.isvstool(cfg) then
			oldfn(cfg)
		end
	end)

	premake.override(vc2010, "entryPointSymbol", function(oldfn, cfg)
		if not m.isgccorclang(cfg) then
			oldfn(cfg)
		end
	end)


--
-- Add options unsupported by vs-tool vs-tool UI to <AdvancedOptions>.
--
	function m.additionalOptions(cfg, condition)

		local function alreadyHas(t, key)
			for _, k in ipairs(t) do
				if string.find(k, key) then
					return true
				end
			end
			return false
		end

--		Eg: table.insert(cfg.buildoptions, "-option")

	end

	return m
